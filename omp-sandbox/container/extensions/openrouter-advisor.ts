// OpenRouter Advisor server-tool extension for OMP.
//
// Wires up the OpenRouter `openrouter:advisor` server tool as an OMP extension
// so the agent can consult a stronger model mid-generation when stuck —
// pull-based, zero cost on trivial turns. OpenRouter intercepts the tool call
// server-side and executes it; the agent sees the advice inline as a tool result.
//
// Two hooks (mirrors the Hermes plugin pattern):
//
//   1. pi.registerTool(): advertises the advisor to the model with a no-op stub
//      handler. The stub is a safety net — if OpenRouter's server-side
//      interception does not fire, the agent gets a clear diagnostic instead of
//      a silent failure.
//
//   2. pi.on("before_provider_request"): injects the real
//      { type: "openrouter:advisor", parameters: { name, model, ... } }
//      declaration into the outgoing request's `tools` array. The `name`
//      parameter matches the registered stub so the model sees exactly one
//      advisor tool; OpenRouter intercepts the call server-side before OMP
//      ever sees it.
//
// Configuration:
//   A JSON config file sits next to this extension at
//   `openrouter-advisor.json` and lists every advisor parameter with its
//   default value. Edit it to change behavior without touching code.
//   Environment variables override config-file values at deploy time:
//     OMP_ADVISOR_MODEL    — advisor model spec
//     OMP_ADVISOR_DISABLED — set to "1" to disable the extension
//   Precedence: env var > config file > hardcoded defaults.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

import { readFileSync } from "fs";

const ADVISOR_TOOL_NAME = "openrouter_advisor";
const SERVER_TOOL_TYPE = "openrouter:advisor";
// Resolve config file next to this extension. `new URL` with a relative ref
// drops the `?mtime=` cache-buster Bun appends to import.meta.url.
const CONFIG_URL = new URL("openrouter-advisor.json", import.meta.url);

/** Resolved advisor configuration after merging defaults, config file, and env overrides. */
interface AdvisorConfig {
  disabled: boolean;
  model: string;
  max_tool_calls: number;
  instructions: string | null;
  forward_transcript: boolean;
  max_completion_tokens: number | null;
  temperature: number | null;
}

const DEFAULTS: AdvisorConfig = {
  disabled: false,
  model: "qwen/qwen3.8-max",
  max_tool_calls: 5,
  instructions: null,
  forward_transcript: false,
  max_completion_tokens: null,
  temperature: null,
};

/** Shape of the outgoing provider request payload we mutate. */
interface ProviderRequestPayload {
  tools?: unknown[];
}

/** Type guard: is this tool entry the advisor server-tool declaration? */
function isAdvisorServerTool(entry: unknown): boolean {
  if (typeof entry !== "object" || entry === null) return false;
  if (!("type" in entry) || typeof entry.type !== "string") return false;
  return entry.type === SERVER_TOOL_TYPE;
}

/**
 * Read `openrouter-advisor.json` next to this extension and merge over the
 * hardcoded defaults. Errors are logged but never fatal — a missing or
 * unparseable config file falls back to DEFAULTS.
 */
function loadConfig(logger: ExtensionAPI["logger"] | undefined): AdvisorConfig {
  try {
    const raw = readFileSync(CONFIG_URL, "utf-8");
    return { ...DEFAULTS, ...JSON.parse(raw) };
  } catch (err) {
    logger?.debug?.(`[advisor] config file not read (${String(err)}) — using defaults`);
    return { ...DEFAULTS };
  }
}

/**
 * Apply environment-variable overrides on top of the config-file values.
 * Env vars are the deploy-time escape hatch; config-file is for persistent
 * user preferences.
 */
function applyEnvOverrides(cfg: AdvisorConfig): AdvisorConfig {
  if (process.env.OMP_ADVISOR_MODEL) cfg.model = process.env.OMP_ADVISOR_MODEL;
  if (process.env.OMP_ADVISOR_DISABLED === "1") cfg.disabled = true;
  return cfg;
}

/**
 * Build the `parameters` object for the injected server-tool declaration.
 * Omits keys whose value is `null` (meaning "use provider default") so we
 * don't send unnecessary fields on the wire.
 */
function buildAdvisorParameters(cfg: AdvisorConfig): Record<string, unknown> {
  const params: Record<string, unknown> = {
    name: ADVISOR_TOOL_NAME,
    model: cfg.model,
  };
  if (cfg.max_tool_calls != null) params.max_tool_calls = cfg.max_tool_calls;
  if (cfg.instructions != null) params.instructions = cfg.instructions;
  if (cfg.forward_transcript) params.forward_transcript = true;
  if (cfg.max_completion_tokens != null) params.max_completion_tokens = cfg.max_completion_tokens;
  if (cfg.temperature != null) params.temperature = cfg.temperature;
  return params;
}

export default function (pi: ExtensionAPI) {
  const cfg = applyEnvOverrides(loadConfig(pi.logger));

  if (cfg.disabled) {
    pi.logger?.info("[advisor] disabled via config or OMP_ADVISOR_DISABLED=1");
    return;
  }

  pi.logger?.info(`[advisor] loaded — model=${cfg.model} max_tool_calls=${cfg.max_tool_calls}`);
  const { z } = pi.zod;

  // 1. Advertise the advisor to the model with a no-op stub handler.
  //    OpenRouter intercepts the call server-side before OMP ever sees it;
  //    this handler is only reached if interception fails (a safety net).
  pi.registerTool({
    name: ADVISOR_TOOL_NAME,
    label: "OpenRouter Advisor",
    description:
      "Consult a stronger advisor model mid-generation. Call this when you hit a decision point — before committing to an approach, when you're stuck, or before declaring a task done. Do NOT call it for trivial steps you can resolve directly. Pass a `prompt` describing what you need advice on.",
    parameters: z.object({
      prompt: z
        .string()
        .describe("What you want advice on. Describe the decision, problem, or verification you need help with."),
    }),
    async execute(_toolCallId, params: { prompt: string }) {
      return {
        content: [
          {
            type: "text",
            text: `[advisor] OpenRouter server-side interception did not fire. The advisor is a server tool executed by OpenRouter — this stub should never produce real advice. Prompt was: ${params.prompt}`,
          },
        ],
        details: { stub: true },
      };
    },
  });

  // 2. Inject the real server-tool declaration into each outgoing request.
  //    Gated to OpenRouter-bound requests so a future non-OpenRouter provider
  //    doesn't 400 on the unknown tool type.
  const advisorParameters = buildAdvisorParameters(cfg);

  pi.on("before_provider_request", (event, ctx) => {
    if (event.payload == null || typeof event.payload !== "object") return;
    if (ctx.model?.provider !== "openrouter") return;

    const payload = event.payload as ProviderRequestPayload;
    if (!Array.isArray(payload.tools)) return;

    // Don't double-inject if already present.
    if (payload.tools.some(isAdvisorServerTool)) return;

    payload.tools.push({
      type: SERVER_TOOL_TYPE,
      parameters: advisorParameters,
    });
  });
}
