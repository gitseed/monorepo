# Veronica, a phone-callable voice agent

Veronica is a voice agent you reach by calling a phone number. Twilio
answers the call and hands it to OpenAI's Realtime API over SIP;
[gpt-realtime](https://developers.openai.com/api/docs/guides/realtime-sip)
does the talking. Everything else runs on Cloudflare, deployed as one
Worker application (`app/`):

- The **voice Worker** (`app/src`) plays switchboard: it tells Twilio
  where to ring the call, and when OpenAI asks "should I take this?" it
  checks the caller against the contacts KV namespace — rejecting
  strangers, and dispatching known callers to their own session-driver
  container. It never answers a call itself.
- The **session driver** (`app/driver`, a Go program in a Cloudflare
  Container) is what picks up. Each call gets its own container, addressed
  by `call_id` through a Durable Object: the dispatch itself starts it
  (cold start is seconds — the reason this platform hosts the driver), and
  the driver accepts the call with Veronica's persona (ringing stops
  here), attaches the call's WebSocket, speaks the greeting, and holds the
  socket for the whole call — re-checking the allowlist (a removed caller
  is hung up on within a minute) and, soon, handling tool calls. Because
  the driver owns the call from its first moment, nothing will escape the
  transcript when transcript logging lands. When the call ends the process
  exits and the container stops: the container's lifetime is the call's,
  and nothing runs — or bills — between calls. Simultaneous calls simply
  get simultaneous containers.

Audio never touches either program — it flows Twilio↔OpenAI directly over
SIP.

The Worker's public face is a fixed URL on a domain we own,
`voice.veronica-agent.com`, claimed as a Workers custom domain — the zone
already lives on Cloudflare, so there is no load balancer, no origin, and
no always-on infrastructure cost; the stack's only fixed cost is the
Workers Paid plan ($5/month). The URLs configured at OpenAI and Twilio are
write-once, whatever happens behind them.

The repo is two roots:

- `app/` is the Cloudflare deployable: the Worker source, the driver's Go
  module, and `wrangler.template.jsonc` tying them together. `wrangler
  deploy` deploys the Worker, points the container at the pre-built
  driver image, and claims the custom domain.
- `tofu/` (pinned providers, `veronica` workspace, the state backend from
  `lightning`) owns everything the deploy stands on: the contacts KV
  namespace with one key per name in `allowed_callers.txt` (the numbers
  typed into the dashboard so they never enter the repo), the Twilio
  number, the zone's SSL setting, and the driver image itself — built
  remotely by Cloud Build into Artifact Registry whenever the driver
  source changes (no local Docker anywhere), tagged with the source hash
  so every tag is immutable. The apply then renders the workspace's
  actual `app/wrangler.jsonc` (gitignored) from the template, stitching
  in the workspace values — worker name, hostname, contacts namespace id,
  the image tag it just built, and Veronica's persona from `workspace.tf`
  — so one template serves every workspace. Cloudflare pulls the image
  from Artifact Registry as a dedicated read-only service account,
  registered automatically by tofu (see `tofu/registries.tf`).

The driver keeps the established Go shape: a thin entry point
(`cmd/driver`) over `internal/` packages split by who they talk to —
`realtime` speaks to the OpenAI platform, `contacts` reads the allowlist
back through the Worker, and `session` holds the driver's actual flow. The
pure logic has table tests; `go test ./...` in `app/driver` runs them.

## Prerequisites

- OpenTofu `1.12.3`, Node 22+, and the `gcloud` CLI (the apply hands image
  builds to Cloud Build; nothing builds locally)
- Google application-default credentials with access to the project in
  `tofu/workspace.tf` (`gcloud auth login` and
  `gcloud auth application-default login`)
- The same `cloudflare` AWS profile used by `lightning`, with access to its
  R2 bucket named `tofu` (the state backend)
- `CLOUDFLARE_API_TOKEN` exported, with edit access to Workers scripts,
  KV, and the zone in `tofu/workspace.tf` (`veronica-agent.com`); wrangler
  uses the same variable
- `TWILIO_API_KEY` and `TWILIO_API_SECRET` exported for the provider (the
  account SID and auth token)
- An OpenAI account with API billing enabled (the Realtime API is not
  covered by a ChatGPT subscription); its project id lives in
  `tofu/workspace.tf` as `openai_project_id`

## Deploy

[SETUP.md](SETUP.md) walks the whole deployment in order — the tofu apply,
the console steps (caller numbers, the OpenAI webhook endpoint and API
key, the secrets), and the wrangler deploy — through a working phone call.

## How a call works

1. Twilio answers the number and POSTs to the Worker's `/twiml` route,
   which replies with `<Dial answerOnBridge><Sip>` pointing at
   `sip:<project>@sip.api.openai.com` — the call rings through to OpenAI
   while the caller still hears ringing.
2. OpenAI POSTs a signed `realtime.call.incoming` webhook to the Worker's
   `/openai-webhook` route. The Worker verifies the signature, reads the
   contacts KV namespace, and rejects the call (SIP 603) unless the
   caller's number matches an entry — presence of a number authorizes the
   caller.
3. A known caller is dispatched: the Worker fetches the Durable Object
   named by the `call_id`, which starts that call's container and forwards
   the dispatch to the driver's `/call` endpoint. The caller keeps hearing
   ringing — nothing has answered yet.
4. The driver accepts the call with the session config — model, voice, and
   Veronica's instructions, from `tofu/workspace.tf`. The ringing stops:
   this is the pickup. It attaches the call's WebSocket in the same breath
   (the webhook is answered only once both have happened, so a failure
   makes OpenAI redeliver — idempotently, to the same container), waits a
   beat for the audio path to bridge, and nudges Veronica into speaking
   the greeting first.
5. The driver stays on the line until the call ends and the socket closes,
   then exits, stopping its container. A second call during the first gets
   its own container; neither waits on the other.

Changing a caller's number is a KV dashboard edit — it takes effect on the
next call (and, for removals, on live calls within a minute). Adding or
removing a *name* means editing `allowed_callers.txt` and applying `tofu/`.
Changing the persona, voice, or model is an edit to `tofu/workspace.tf`,
an apply (which re-renders `app/wrangler.jsonc`), and a `wrangler deploy`.
Changing the driver's code is an apply (which rebuilds the image and pins
the new tag into the config) and the same deploy; Worker code alone is
just the deploy.

## Operations

```bash
# Live logs from the Worker and the driver containers:
cd app && npm run tail

# The same logs, searchable, in the dashboard: Workers & Pages ->
# veronica-voice -> Logs. Container instances and their status are under
# the worker's Containers tab.

# Inspect the resolved outputs (from tofu/):
tofu output
```

Call records (including SIP responses from OpenAI) are in the Twilio
console's call log; session activity is on platform.openai.com under Logs.

## Security notes

- The two real credentials — the OpenAI API key and webhook signing secret
  — live only as Worker secrets uploaded with `wrangler secret put`; they
  are never in the repo, in OpenTofu variables, or in state.
- The webhook route only acts on requests carrying a valid Standard
  Webhooks HMAC signature from OpenAI; the TwiML route serves a static
  instruction whose only payload is the (non-secret) OpenAI project id.
- The callers' phone numbers live in the contacts KV namespace — typed
  into the dashboard, never in the repo, which carries only their names.
- The inbound allowlist is caller-ID filtering, not authentication; caller
  ID can be spoofed, so do not treat the phone line as a trusted control
  channel.
- The driver container holds no Cloudflare credentials: its allowlist
  reads go to a virtual hostname the Worker intercepts and answers from
  KV. The only secret it sees is the OpenAI key the accept requires.
- Cloudflare does not guarantee a container instance survives its whole
  call (hosts restart irregularly). A mid-call restart today loses the
  driver but not the call — the SIP audio continues; re-attaching is on
  the TODO list.
- Destroying the Twilio number resource releases the number permanently,
  so it carries `prevent_destroy`.
