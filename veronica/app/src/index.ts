// Veronica's voice front door, as a Cloudflare Worker.
//
// The call path: Twilio answers the phone number and fetches /twiml, which
// hands the call to OpenAI over SIP. OpenAI then asks us whether to take
// the call by POSTing a signed realtime.call.incoming webhook to
// /openai-webhook; we check the caller against the contacts KV namespace,
// rejecting strangers and dispatching known callers to their own session
// driver container (driver.ts) — which is what picks up. This Worker never
// answers a call itself, and audio flows Twilio<->OpenAI directly, so
// nothing here touches media.
import { Driver } from "./driver";
import { allowedNumbers } from "./contacts";
import { twiml, verifySignature, callerNumber, rejectCall, type IncomingCall } from "./openai";

export { Driver };
// The outbound interception behind Driver.outboundByHost runs through this
// entrypoint; the runtime looks it up on the worker's exports at container
// start and refuses to start without it.
export { ContainerProxy } from "@cloudflare/containers";

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/twiml") {
      return twiml(env);
    }
    if (request.method === "POST" && url.pathname === "/openai-webhook") {
      return openaiWebhook(request, env);
    }
    return new Response("not found", { status: 404 });
  },
} satisfies ExportedHandler<Env>;

async function openaiWebhook(request: Request, env: Env): Promise<Response> {
  const body = await request.text();
  if (!(await verifySignature(request, body, env.OPENAI_WEBHOOK_SECRET))) {
    console.error("webhook rejected: bad or missing signature");
    return new Response("bad signature", { status: 401 });
  }

  const event: IncomingCall = JSON.parse(body);
  if (event.type !== "realtime.call.incoming") {
    return new Response("ignored", { status: 200 });
  }

  const callId = event.data?.call_id;
  if (!callId) {
    return new Response("ignored", { status: 200 });
  }
  const from = callerNumber(event.data?.sip_headers ?? []);
  const allowed = await allowedNumbers(env);
  if (!from || !allowed.has(from)) {
    console.error(`call rejected: caller ${from ?? "unknown"} not in allowlist`);
    await rejectCall(env, callId);
    return new Response("rejected", { status: 200 });
  }

  // The dispatch: fetching the call's own container starts it and hands it
  // the call; the response comes back once the driver has accepted (the
  // pickup — ringing stops there) and attached the sideband socket. A
  // redelivered webhook lands on the same container and is acknowledged
  // idempotently.
  console.log(`dispatching call ${callId} from ${from} to its driver`);
  const driver = env.DRIVER.getByName(callId);
  const response = await driver.fetch("http://driver/call", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ call_id: callId, caller: from }),
  });
  if (!response.ok) {
    // Non-2xx makes OpenAI redeliver the webhook: the retry, not this
    // request, is the recovery mechanism.
    console.error(`driver for call ${callId} failed: ${response.status} ${await response.text()}`);
    return new Response("driver failed", { status: 500 });
  }
  console.log(`call ${callId} from ${from}: ${await response.text()}`);
  return new Response("dispatched", { status: 200 });
}
