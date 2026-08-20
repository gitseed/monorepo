// The session driver's Cloudflare side: a Container-backed Durable Object,
// one per call_id. The Worker dispatches a call by fetching this object;
// the base class starts the container (cold start is seconds — the whole
// reason this platform was chosen), waits for the driver's port, and
// forwards the dispatch to the Go process, which accepts the call, holds
// the line, and exits when the call ends — stopping the container, so
// nothing runs between calls.
import { Container } from "@cloudflare/containers";
import { allowedNumbers } from "./contacts";

export class Driver extends Container<Env> {
  defaultPort = 8080;

  // A safety fuse only, not the lifecycle: the timer counts inbound
  // activity, which a held-open outbound WebSocket is not, so this must
  // stay above the driver's 55-minute session cap. Normal cleanup is the
  // Go process exiting with its call.
  sleepAfter = "1h";

  constructor(ctx: ConstructorParameters<typeof Container>[0], env: Env) {
    super(ctx, env);
    // The container's whole configuration: the persona and the key to
    // accept with. The call itself arrives in the dispatch request.
    this.envVars = {
      OPENAI_API_KEY: env.OPENAI_API_KEY,
      VOICE_MODEL: env.VOICE_MODEL,
      VOICE_VOICE: env.VOICE_VOICE,
      VOICE_GREETING: env.VOICE_GREETING,
      VOICE_GREETING_SETTLE_MS: env.VOICE_GREETING_SETTLE_MS,
      VOICE_INSTRUCTIONS: env.VOICE_INSTRUCTIONS,
    };
  }
}

// The driver's mid-call allowlist checks: its requests to the
// contacts.internal virtual host never leave Cloudflare — they are
// intercepted here and answered from the contacts KV namespace, so the
// container needs no credentials of its own.
Driver.outboundByHost = {
  "contacts.internal": async (_request: Request, env: Env) =>
    Response.json([...(await allowedNumbers(env))]),
};
