// OpenRouter Advisor suite — each JSON file in `openrouter-advisor/advisors/` defines one
// tool the model can call mid-generation for guidance. Pull-based, zero
// cost on trivial turns.
//
// Configuration:
//   One JSON file per advisor tool in `openrouter-advisor/advisors/` next to this extension.
//   Each file must set `name` (the tool name) and may override any default.
//   Edit the JSON to change behavior without touching code.
//   Environment variable:
//     OMP_ADVISORS_DISABLED — set to "1" to disable all advisor tools.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

import { readFileSync, readdirSync } from "node:fs";

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

/** Resolved advisor configuration after merging defaults with a JSON config file. */
interface AdvisorConfig {
  /** Tool name registered with the model. Must be unique across all advisor configs. */
  name: string;
  disabled: boolean;
  model: string;
  /** Tool description shown to the model. */
  description: string;
  /** Tool label shown in UI. */
  label: string;
  /** System prompt for the advisor model. */
  instructions: string;
  fallback_models: string[];
  /** Total wall-clock cap for one consultation. */
  timeout_ms: number;
  /** Max silence between stream chunks before the advisor is considered stalled. */
  idle_timeout_ms: number;
  max_tokens: number | null;
  temperature: number | null;
  /** OpenRouter unified reasoning config, e.g. { "effort": "medium" }. */
  reasoning: Record<string, unknown> | null;
}

const DEFAULTS: Omit<AdvisorConfig, "name"> = {
  disabled: false,
  model: "qwen/qwen3.8-max",
  description:
    "Consult a higher-intelligence advisor model for strategic guidance, then continue your work informed by its advice. Use it before committing to an approach on a complex task, when you are stuck, or before declaring a task done.",
  label: "OpenRouter Advisor",
  instructions: "You are a strategic advisor to an AI coding agent. Provide concise, actionable guidance.",
  fallback_models: [],
  timeout_ms: 180_000,
  idle_timeout_ms: 30_000,
  max_tokens: 2000,
  temperature: null,
  reasoning: null,
};

/** Read every `openrouter-advisor/advisors/*.json` next to this extension and merge each over the hardcoded defaults. */
function loadConfigs(logger: ExtensionAPI["logger"] | undefined): AdvisorConfig[] {
  try {
    const dir = new URL("openrouter-advisor/advisors/", import.meta.url);
    const files = readdirSync(dir).filter((f) => f.endsWith(".json"));
    return files.map((f) => {
      const raw = readFileSync(new URL(f, dir), "utf-8");
      return { ...DEFAULTS, ...JSON.parse(raw) } as AdvisorConfig;
    });
  } catch (err) {
    logger?.debug?.(`[advisor] no configs loaded (${String(err)})`);
    return [];
  }
}

interface StreamDelta {
  choices?: Array<{ delta?: { content?: string } }>;
  error?: { message?: string };
  model?: string;
}

export default function (pi: ExtensionAPI) {
  if (process.env.OMP_ADVISORS_DISABLED === "1") {
    pi.logger?.info("[advisor] disabled via OMP_ADVISORS_DISABLED=1");
    return;
  }

  const configs = loadConfigs(pi.logger).filter((c) => !c.disabled);
  if (configs.length === 0) {
    pi.logger?.info("[advisor] no enabled advisor configs found");
    return;
  }

  pi.logger?.info(`[advisor] loaded ${configs.length} tool(s): ${configs.map((c) => c.name).join(", ")}`);

  const { z } = pi.zod;

  for (const cfg of configs) {
    pi.logger?.info(
      `[advisor] ${cfg.name} — model=${cfg.model} timeout=${cfg.timeout_ms}ms idle=${cfg.idle_timeout_ms}ms` +
        (cfg.fallback_models.length ? ` fallbacks=${cfg.fallback_models.join(",")}` : ""),
    );

    pi.registerTool({
      name: cfg.name,
      label: cfg.label,
      description: cfg.description,
      parameters: z.object({
        prompt: z
          .string()
          .describe("What you need advice on. Describe the decision, problem, or verification you need help with."),
      }),
      async execute(
        _toolCallId: string,
        params: { prompt: string },
        signal?: AbortSignal,
        onUpdate?: (update: { content: Array<{ type: "text"; text: string }> }) => void,
      ) {
        const body: Record<string, unknown> = {
          model: cfg.model,
          stream: true,
          messages: [
            {
              role: "system",
              content: cfg.instructions,
            },
            { role: "user", content: params.prompt },
          ],
        };

        if (cfg.fallback_models.length > 0) {
          body.models = [cfg.model, ...cfg.fallback_models];
          delete body.model;
        }
        if (cfg.max_tokens != null) body.max_tokens = cfg.max_tokens;
        if (cfg.temperature != null) body.temperature = cfg.temperature;
        if (cfg.reasoning != null) body.reasoning = cfg.reasoning;

        // Three ways out: framework abort, total cap, or idle timeout. The idle
        // timer resets on every received chunk, so a slow-but-streaming advisor
        // is never killed while a wedged one dies after idle_timeout_ms.
        const totalSignal = AbortSignal.timeout(cfg.timeout_ms);
        const idleController = new AbortController();
        let idleTimer: ReturnType<typeof setTimeout> | undefined;
        const resetIdle = () => {
          clearTimeout(idleTimer);
          idleTimer = setTimeout(() => idleController.abort(), cfg.idle_timeout_ms);
        };
        const signals = [totalSignal, idleController.signal];
        if (signal) signals.push(signal);
        const combinedSignal = AbortSignal.any(signals);

        let advice = "";
        let responseModel = "";

        try {
          onUpdate?.({ content: [{ type: "text", text: `Consulting ${cfg.label}...` }] });

          const apiKey = process.env.OPENROUTER_API_KEY;
          if (!apiKey) {
            return {
              content: [
                { type: "text", text: `[${cfg.name}] OPENROUTER_API_KEY is not set. Proceed with your own judgment.` },
              ],
              isError: true,
            };
          }
          resetIdle();

          const res = await fetch(OPENROUTER_URL, {
            method: "POST",
            headers: {
              Authorization: `Bearer ${apiKey}`,
              "Content-Type": "application/json",
              "HTTP-Referer": "https://github.com/gitseed/monorepo",
              "X-Title": "OMP Advisor Extension",
            },
            body: JSON.stringify(body),
            signal: combinedSignal,
          });

          if (!res.ok) {
            const errText = await res.text().catch(() => res.statusText);
            return {
              content: [
                {
                  type: "text",
                  text: `[${cfg.name}] OpenRouter returned ${res.status}: ${errText}. Proceed with your own judgment.`,
                },
              ],
              isError: true,
            };
          }

          if (!res.body) {
            return {
              content: [{ type: "text", text: `[${cfg.name}] Empty response body. Proceed with your own judgment.` }],
              isError: true,
            };
          }

          // SSE parse: `data: {json}` lines carry deltas, `: ...` comment lines
          // are OpenRouter keepalives, `data: [DONE]` ends the stream. Any
          // received chunk — keepalives included — resets the idle timer.
          const reader = res.body.getReader();
          const decoder = new TextDecoder();
          let buf = "";
          let lastUpdate = 0;
          let done = false;

          while (!done) {
            const { done: eof, value } = await reader.read();
            if (eof) break;
            resetIdle();
            buf += decoder.decode(value, { stream: true });

            let nl: number;
            while ((nl = buf.indexOf("\n")) !== -1) {
              const line = buf.slice(0, nl).trim();
              buf = buf.slice(nl + 1);
              if (!line || line.startsWith(":") || !line.startsWith("data:")) continue;
              const payload = line.slice(5).trim();
              if (payload === "[DONE]") {
                done = true;
                break;
              }
              let parsed: StreamDelta;
              try {
                parsed = JSON.parse(payload);
              } catch {
                continue;
              }
              if (parsed.error) {
                throw new Error(`OpenRouter stream error: ${parsed.error.message ?? JSON.stringify(parsed.error)}`);
              }
              const delta = parsed.choices?.[0]?.delta?.content;
              if (delta) advice += delta;
              if (parsed.model) responseModel = parsed.model;
            }

            const now = Date.now();
            if (advice && now - lastUpdate > 2000) {
              lastUpdate = now;
              onUpdate?.({
                content: [{ type: "text", text: `Streaming advice from ${cfg.label}... (${advice.length} chars)` }],
              });
            }
          }

          if (!advice) {
            return {
              content: [
                { type: "text", text: `[${cfg.name}] Stream ended with no content. Proceed with your own judgment.` },
              ],
              isError: true,
            };
          }

          return {
            content: [{ type: "text", text: advice }],
            details: { model: responseModel || cfg.model },
          };
        } catch (err) {
          if (signal?.aborted) {
            return { content: [{ type: "text", text: "Cancelled" }] };
          }
          // Partial advice beats none — return what streamed before the cutoff,
          // regardless of error type (timeout, abort, or mid-stream error event).
          const isTimeout = idleController.signal.aborted || totalSignal.aborted;
          if (advice) {
            const reason = isTimeout
              ? idleController.signal.aborted
                ? `no data for ${cfg.idle_timeout_ms}ms — advisor stalled`
                : `exceeded total cap of ${cfg.timeout_ms}ms`
              : (err instanceof Error ? err.message : String(err));
            return {
              content: [{ type: "text", text: `${advice}\n\n[${cfg.name}] Advice truncated: ${reason}.` }],
            };
          }
          if (isTimeout) {
            const reason = idleController.signal.aborted
              ? `no data for ${cfg.idle_timeout_ms}ms — advisor stalled`
              : `exceeded total cap of ${cfg.timeout_ms}ms`;
            return {
              content: [{ type: "text", text: `[${cfg.name}] Timed out (${reason}). Proceed with your own judgment.` }],
              isError: true,
            };
          }
          const msg = err instanceof Error ? err.message : String(err);
          return {
            content: [
              { type: "text", text: `[${cfg.name}] Request failed: ${msg}. Proceed with your own judgment.` },
            ],
            isError: true,
          };
        } finally {
          clearTimeout(idleTimer);
        }
      },
    });
  }
}
