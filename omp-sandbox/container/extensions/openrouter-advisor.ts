// OpenRouter Advisor client-side tool extension for OMP.
//
// Lets the agent consult a stronger advisor model mid-generation —
// pull-based, zero cost on trivial turns. The execute handler POSTs
// directly to OpenRouter's chat/completions endpoint with the advisor
// model, so the call has a hard timeout and clean fallback that the
// server-tool design cannot provide.
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

import { readFileSync } from "fs";

const ADVISOR_TOOL_NAME = "openrouter_advisor";
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

/** Resolved advisor configuration after merging defaults, config file, and env overrides. */
interface AdvisorConfig {
  disabled: boolean;
  model: string;
  fallback_models: string[];
  timeout_ms: number;
  instructions: string | null;
  max_completion_tokens: number | null;
  temperature: number | null;
}

const DEFAULTS: AdvisorConfig = {
  disabled: false,
  model: "qwen/qwen3.8-max",
  fallback_models: [],
  timeout_ms: 60_000,
  instructions: null,
  max_completion_tokens: null,
  temperature: null,
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

export default function (pi: ExtensionAPI) {
  const cfg = applyEnvOverrides(loadConfig(pi.logger));

  if (cfg.disabled) {
    pi.logger?.info("[advisor] disabled via config or OMP_ADVISOR_DISABLED=1");
    return;
  }

  pi.logger?.info(
    `[advisor] loaded — model=${cfg.model} timeout=${cfg.timeout_ms}ms` +
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
    async execute(_toolCallId: string, params: { prompt: string }, signal?: AbortSignal) {
      const body: Record<string, unknown> = {
        model: cfg.model,
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
        body.model = undefined;
      }

      if (cfg.max_completion_tokens != null) body.max_completion_tokens = cfg.max_completion_tokens;
      if (cfg.temperature != null) body.temperature = cfg.temperature;

      // Combine the framework-provided abort signal with a hard timeout so an
      // unavailable advisor model becomes a clean error, not a hang.
      const timeoutSignal = AbortSignal.timeout(cfg.timeout_ms);
      const combinedSignal = signal
        ? AbortSignal.any([signal, timeoutSignal])
        : timeoutSignal;

      try {
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

        const data = await res.json() as { choices?: Array<{ message?: { content?: string } }> };

        // Handle routing-fallback responses — extract text from the first choice.
        if (data?.choices?.[0]?.message?.content) {
          return {
            content: [{ type: "text", text: data.choices[0].message!.content }],
          };
        }

        return {
          content: [
            { type: "text", text: `[advisor] Unexpected response shape. Proceed with your own judgment.` },
          ],
          isError: true,
        };
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);

        if (msg === "The operation was aborted" || msg === "The user aborted a request" || msg === "The operation was timed out") {
          return {
            content: [
              {
                type: "text",
                text: `[advisor] Timed out after ${cfg.timeout_ms}ms. Proceed with your own judgment.`,
              },
            ],
            isError: true,
          };
        }

        return {
          content: [
            { type: "text", text: `[advisor] Request failed: ${msg}. Proceed with your own judgment.` },
          ],
          isError: true,
        };
      }
    },
  });
}
