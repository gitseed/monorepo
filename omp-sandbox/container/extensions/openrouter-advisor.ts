// OpenRouter Advisor client-side tool extension for OMP.
//
// Lets the agent consult a stronger advisor model mid-generation —
// pull-based, zero cost on trivial turns. The execute handler streams
// from OpenRouter's chat/completions endpoint, so a stalled advisor is
// detected by silence (idle timeout) rather than a flat deadline that
// false-fires on slow-but-healthy reasoning models.
//
// Configuration:
//   A JSON config file sits next to this extension at
//   `openrouter-advisor.json` and lists every advisor parameter with its
//   default value. Edit it to change behavior without touching code.
//   Environment variables override config-file values at deploy time:
//     OMP_ADVISOR_MODEL    — primary advisor model spec
//     OMP_ADVISOR_DISABLED — set to "1" to disable the extension
//   Precedence: env var > config file > hardcoded defaults.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

import { readFileSync } from "node:fs";

const ADVISOR_TOOL_NAME = "openrouter_advisor";
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

/** Resolved advisor configuration after merging defaults, config file, and env overrides. */
interface AdvisorConfig {
  disabled: boolean;
  model: string;
  fallback_models: string[];
  /** Total wall-clock cap for one consultation. */
  timeout_ms: number;
  /** Max silence between stream chunks before the advisor is considered stalled. */
  idle_timeout_ms: number;
  instructions: string | null;
  max_completion_tokens: number | null;
  temperature: number | null;
  /** OpenRouter unified reasoning config, e.g. { "effort": "medium" }. */
  reasoning: Record<string, unknown> | null;
}

const DEFAULTS: AdvisorConfig = {
  disabled: false,
  model: "qwen/qwen3.8-max",
  fallback_models: [],
  timeout_ms: 180_000,
  idle_timeout_ms: 30_000,
  instructions: null,
  max_completion_tokens: 2000,
  temperature: null,
  reasoning: null,
};

/** Read `openrouter-advisor.json` next to this extension and merge over the hardcoded defaults. */
function loadConfig(logger: ExtensionAPI["logger"] | undefined): AdvisorConfig {
  try {
    const configUrl = new URL("openrouter-advisor.json", import.meta.url);
    const raw = readFileSync(configUrl, "utf-8");
    return { ...DEFAULTS, ...JSON.parse(raw) };
  } catch (err) {
    logger?.debug?.(`[advisor] config file not read (${String(err)}) — using defaults`);
    return { ...DEFAULTS };
  }
}

/** Apply environment-variable overrides on top of the config-file values. */
function applyEnvOverrides(cfg: AdvisorConfig): AdvisorConfig {
  if (process.env.OMP_ADVISOR_MODEL) cfg.model = process.env.OMP_ADVISOR_MODEL;
  if (process.env.OMP_ADVISOR_DISABLED === "1") cfg.disabled = true;
  return cfg;
}

interface StreamDelta {
  choices?: Array<{ delta?: { content?: string } }>;
  error?: { message?: string };
}

export default function (pi: ExtensionAPI) {
  const cfg = applyEnvOverrides(loadConfig(pi.logger));

  if (cfg.disabled) {
    pi.logger?.info("[advisor] disabled via config or OMP_ADVISOR_DISABLED=1");
    return;
  }

  pi.logger?.info(
    `[advisor] loaded — model=${cfg.model} timeout=${cfg.timeout_ms}ms idle=${cfg.idle_timeout_ms}ms` +
      (cfg.fallback_models.length ? ` fallbacks=${cfg.fallback_models.join(",")}` : ""),
  );

  const { z } = pi.zod;

  pi.registerTool({
    name: ADVISOR_TOOL_NAME,
    label: "OpenRouter Advisor",
    description:
      "Consult a higher-intelligence advisor model for strategic guidance, then continue your work informed by its advice. Use it before committing to an approach on a complex task, when you are stuck, or before declaring a task done.",
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
            content:
              cfg.instructions ??
              "You are a strategic advisor to an AI coding agent. Provide concise, actionable guidance.",
          },
          { role: "user", content: params.prompt },
        ],
      };

      if (cfg.fallback_models.length > 0) {
        body.models = [cfg.model, ...cfg.fallback_models];
        delete body.model;
      }

      if (cfg.max_completion_tokens != null) body.max_completion_tokens = cfg.max_completion_tokens;
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

      try {
        onUpdate?.({ content: [{ type: "text", text: `Consulting ${cfg.model}...` }] });
        resetIdle();

        const res = await fetch(OPENROUTER_URL, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${process.env.OPENROUTER_API_KEY ?? ""}`,
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
                text: `[advisor] OpenRouter returned ${res.status}: ${errText}. Proceed with your own judgment.`,
              },
            ],
            isError: true,
          };
        }

        if (!res.body) {
          return {
            content: [{ type: "text", text: "[advisor] Empty response body. Proceed with your own judgment." }],
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
          }

          const now = Date.now();
          if (advice && now - lastUpdate > 2000) {
            lastUpdate = now;
            onUpdate?.({
              content: [{ type: "text", text: `Streaming advice from ${cfg.model}... (${advice.length} chars)` }],
            });
          }
        }

        if (!advice) {
          return {
            content: [
              { type: "text", text: "[advisor] Stream ended with no content. Proceed with your own judgment." },
            ],
            isError: true,
          };
        }

        return {
          content: [{ type: "text", text: advice }],
          details: { model: cfg.model },
        };
      } catch (err) {
        if (signal?.aborted) {
          return { content: [{ type: "text", text: "Cancelled" }] };
        }
        // Partial advice beats none — return what streamed before the cutoff.
        if (idleController.signal.aborted || totalSignal.aborted) {
          const reason = idleController.signal.aborted
            ? `no data for ${cfg.idle_timeout_ms}ms — advisor stalled`
            : `exceeded total cap of ${cfg.timeout_ms}ms`;
          if (advice) {
            return {
              content: [{ type: "text", text: `${advice}\n\n[advisor] Advice truncated: ${reason}.` }],
            };
          }
          return {
            content: [{ type: "text", text: `[advisor] Timed out (${reason}). Proceed with your own judgment.` }],
            isError: true,
          };
        }
        const msg = err instanceof Error ? err.message : String(err);
        return {
          content: [
            { type: "text", text: `[advisor] Request failed: ${msg}. Proceed with your own judgment.` },
          ],
          isError: true,
        };
      } finally {
        clearTimeout(idleTimer);
      }
    },
  });
}
