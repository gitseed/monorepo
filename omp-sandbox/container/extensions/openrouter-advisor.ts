// OpenRouter Advisor server-tool extension for OMP.
//
// Wires up the OpenRouter `openrouter:advisor` server tool as an OMP extension
// so the agent can consult a stronger model mid-generation when stuck —
// pull-based, zero cost on trivial turns. OpenRouter intercepts the tool call
// server-side and executes it; the agent sees the advice inline as a tool result.
//
// Two hooks are needed (mirrors the Hermes plugin pattern):
//
//   1. pi.registerTool(): advertises the advisor to the model with a no-op stub
//      handler. Without the advertisement the model treats an injected server
//      tool as "not directly invocable" and never calls it.
//
//   2. pi.on("before_provider_request"): injects the real
//      { type: "openrouter:advisor", parameters: { ... } } declaration into the
//      outgoing request's `tools` array, so OpenRouter recognises and executes
//      it server-side.
//
// Configuration via environment variables:
//   OMP_ADVISOR_MODEL    — advisor model spec (default: ~anthropic/claude-opus-latest)
//   OMP_ADVISOR_DISABLED — set to "1" to disable the extension at load time

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

const ADVISOR_TOOL_NAME = "openrouter_advisor";
const ADVISOR_MODEL_DEFAULT = "~anthropic/claude-opus-latest";
const SERVER_TOOL_TYPE = "openrouter:advisor";

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

export default function (pi: ExtensionAPI) {
  if (process.env.OMP_ADVISOR_DISABLED === "1") {
    pi.logger?.info("[advisor] OMP_ADVISOR_DISABLED=1 — extension disabled");
    return;
  }

  const advisorModel = process.env.OMP_ADVISOR_MODEL || ADVISOR_MODEL_DEFAULT;
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
    hidden: false,
    defaultInactive: false,
    deferrable: false,
    async execute(_toolCallId, params) {
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
  pi.on("before_provider_request", (event) => {
    if (event.payload == null || typeof event.payload !== "object") return;
    const payload = event.payload as ProviderRequestPayload;
    if (!Array.isArray(payload.tools)) return;

    // Don't double-inject if already present.
    if (payload.tools.some(isAdvisorServerTool)) return;

    payload.tools.push({
      type: SERVER_TOOL_TYPE,
      parameters: { model: advisorModel },
    });
  });
}
