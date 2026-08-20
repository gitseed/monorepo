// Speaking to the OpenAI platform: webhook signature verification, caller
// extraction, TwiML pointing Twilio at OpenAI's SIP endpoint, and the
// reject control call. Accepting is not here — that happens in the session
// driver (see driver.ts), so the driver owns the call from its first
// moment. Rejecting stays here because spinning a container up to say no
// would be absurd.

// answerOnBridge keeps the caller hearing ringing until the driver
// accepts, so a rejected caller gets a decline instead of a
// connect-then-hangup; the timeout leaves room for the driver's container
// to start before Twilio gives up on the ringing.
export function twiml(env: Env): Response {
  const sip = `sip:${env.OPENAI_PROJECT_ID}@sip.api.openai.com;transport=tls`;
  return new Response(
    '<?xml version="1.0" encoding="UTF-8"?>' +
      '<Response><Dial answerOnBridge="true" timeout="60">' +
      `<Sip>${xmlEscape(sip)}</Sip>` +
      "</Dial></Response>",
    { headers: { "Content-Type": "text/xml" } },
  );
}

// Standard Webhooks: HMAC-SHA256 over "<id>.<timestamp>.<body>" with the
// base64 secret after the whsec_ prefix; the signature header holds
// space-separated "v1,<base64>" candidates.
export async function verifySignature(request: Request, body: string, secret: string): Promise<boolean> {
  const id = request.headers.get("webhook-id");
  const timestamp = request.headers.get("webhook-timestamp");
  const signatures = request.headers.get("webhook-signature");
  if (!id || !timestamp || !signatures || !secret) {
    return false;
  }
  if (Math.abs(Date.now() / 1000 - Number(timestamp)) > 300) {
    return false;
  }
  const key = await crypto.subtle.importKey(
    "raw",
    Uint8Array.from(atob(secret.replace(/^whsec_/, "")), (c) => c.charCodeAt(0)),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${id}.${timestamp}.${body}`)),
  );
  return signatures.split(" ").some((candidate) => {
    const [version, signature] = candidate.split(",", 2);
    if (version !== "v1" || !signature) {
      return false;
    }
    let given;
    try {
      given = Uint8Array.from(atob(signature), (c) => c.charCodeAt(0));
    } catch {
      return false;
    }
    return given.length === mac.length && crypto.subtle.timingSafeEqual(given, mac);
  });
}

interface SipHeader {
  name?: string;
  value?: string;
}

export interface IncomingCall {
  type?: string;
  data?: {
    call_id?: string;
    sip_headers?: SipHeader[];
  };
}

export function callerNumber(sipHeaders: SipHeader[]): string | null {
  const from = sipHeaders.find((h) => h.name?.toLowerCase() === "from");
  return from?.value?.match(/\+[0-9]+/)?.[0] ?? null;
}

// 603 is SIP for "decline": the caller hears the line refuse, not ring out.
export async function rejectCall(env: Env, callId: string): Promise<void> {
  const response = await fetch(
    `https://api.openai.com/v1/realtime/calls/${encodeURIComponent(callId)}/reject`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ status_code: 603 }),
    },
  );
  if (!response.ok) {
    console.error(`reject for call ${callId} failed: ${response.status} ${await response.text()}`);
  }
}

function xmlEscape(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
