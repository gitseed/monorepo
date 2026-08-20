# Retrospective: how Veronica got here

Written by Claude Fable 5 in July 2026, at the end of its run on this
project. README.md documents what the system *is*; this documents the
path — five architectures, the physics that killed four of them, and the
habits that made the fifth one land. It is addressed to whichever agent
continues the work, on the theory that the expensive lessons should only
be paid for once.

## The one constraint that shaped everything

A phone call gives you roughly **15–20 seconds of ringing** before OpenAI
abandons the unanswered SIP leg and the caller hears a server error. Every
architecture this project has had lived or died by whether it could get a
process attached to the call inside that budget. When you evaluate any
future change, start there: *what does this do to the time between the
webhook and the accept?*

The other invariants, hard-won and worth not relearning:

- **The accept is the pickup.** Ringing stops when something POSTs
  `/accept` with the persona. Whoever accepts owns the call's first
  moment — which is why the driver, not the webhook, must accept
  (otherwise the opening of every call escapes the future transcript).
- **The sideband WebSocket is a control channel, not the call.** Dropping
  it does not hang up. This makes crash recovery and re-attach possible,
  and it means a driverless call is degraded, not dead.
- **Audio never touches this codebase.** It flows Twilio↔OpenAI over SIP.
  Everything here is control plane; latency budgets are about signaling,
  never media.
- **The fixed hostname is load-bearing.** The URLs configured at OpenAI
  and Twilio are write-once; every migration survived because
  `voice.veronica-agent.com` outlived the infrastructure behind it.

## The five eras, and why each ended

1. **OpenClaw VM + voice-call plugin.** Died upstream: the plugin's
   turn-based Twilio inbound answers with a leading `<Pause>`, which never
   answers the call at all. Lesson: read the vendored plugin source before
   trusting its happy path.
2. **OpenClaw + custom ConversationRelay bridge.** Worked end to end,
   retired by economics and ambition: $0.07/min for STT+TTS, and the
   realtime API did the same job better.
3. **Cloudflare Worker (first time).** Worked, retired deliberately: a
   Worker could verify, accept, and nudge a greeting, but could not *hold*
   the socket for a whole call — no tools, no mid-call enforcement.
4. **GCP: webhook function + Cloud Run job, then worker pool.** The
   architecture was right (dispatch/pickup split, driver owns the accept)
   but the platform wasn't: Cloud Run jobs schedule in ~1m42, and manual
   worker-pool scaling reconciles in ~1m32 — both against a 15–20s
   budget. Only Cloud Run's *request* path starts containers in seconds,
   and nothing about our shape fit the request path. The killing mistake
   was mine: I asserted pools rode the fast machinery without measuring.
   **When a design depends on a latency number, measure the number
   first.**
5. **Cloudflare Containers (current).** `getByName(call_id)` gives one
   container per call, started by the dispatch itself, cold in ~1–3s.
   The platform's native model *is* this project's architecture, which is
   why this era took one evening instead of a week. Concurrent calls,
   which the pool era quietly serialized, work for free.

## What actually worked as method

- **Mine the vendored source when docs run out.** The undocumented
  registries API's request body, the Secrets-Store-reference form of the
  credential, and the fact that the GAR key is *already* base64 all came
  from reading wrangler's bundled client in `node_modules` — not from
  guessing, and not from the web. The one bug that reached production
  from guessing (a double-base64) is exactly the bug source-reading
  prevents.
- **Verify with read-only calls before writing config.** The permission
  group name (`Workers Containers Write`), the single Secrets Store, the
  account that actually owns the zone, the registries list response shape
  (`domain` is the identity; there is no `id`) — each was one curl away,
  and each guess avoided was an apply-cycle saved.
- **Validate everything before presenting it.** `tofu validate` + `plan
  -lock=false`, `go build ./... && go vet && go test`, `tsc --noEmit`,
  and a dry-run render of any template. Work that doesn't validate is
  worth zero to the human who has to hand it back (this is not a
  metaphor; it was scored as zero).
- **The first-item-of-a-list trap, twice.** `max_items = 1` on an
  accounts lookup silently picked the wrong Cloudflare account — in this
  repo *and*, independently, in the token generator that was supposed to
  fix it. List everything, select by exact name, and postcondition the
  match. Any API that returns "the first one" is a bug you haven't met
  yet.
- **Let error messages be load-bearing.** `ctx.exports.ContainerProxy is
  undefined` named its own one-line fix. The attach 404's response body
  (`call_id_not_found`) cracked the whole jobs-era mystery — but only
  because the client was written to include response bodies in its
  errors. Write errors that carry the server's words.

## Platform traps for the successor

- **mastercard/restapi must stay on 2.x.** The 3.0.0 framework rewrite
  rejects unknown provider-config values at plan time, which breaks the
  create-the-token-and-use-it-in-one-apply bootstrap.
- **Registry records are identified by `domain`** (`id_attribute =
  "domain"`); the API has no update verb (hence `force_new`) and no
  single-object GET (hence no `tofu import` for it).
- **Cloudflare does not cache external-registry images.** The GAR pull
  may sit on the cold-start path. The image being a few MB of static Go
  on distroless is what keeps this a non-issue; guard that property.
- **`sleepAfter` counts inbound requests only.** A held outbound
  WebSocket is invisible to it. The 1h fuse must stay above the 55-min
  session cap.
- **No instance-longevity guarantee.** Hosts restart; a mid-call restart
  currently orphans the driver (call survives, driverless). The re-attach
  hardening in TODO.md is real work, not paranoia: store the call in the
  Durable Object, re-attach without greeting on restart.
- **Cloud Build IAM propagation is slow.** New service-account grants can
  take a minute to become real; the 60s `time_sleep` exists because 5s
  lost the race in production.
- **The cloudflare v5 provider diffs what the API returns.** Fully
  specify defaults (observability was the worker-era example) or enjoy
  perpetual in-place updates.

## Working with Paul

The standing rules are in the repo's memory and they are not
suggestions: he runs every apply, deploy, and cloud mutation himself —
you prepare, validate, and plan (always `-lock=false`). Secrets never
pass through OpenTofu variables or state, with deliberate, discussed
exceptions for narrow-scope credentials (the pull SA key, the registries
token). Phone numbers never enter the repo. Discuss design before
implementing; explain unusual commands before running them; when docs and
your training disagree, go find a primary source.

He grades from his own seat: interventions cost heavily, unvalidated
work is worth nothing, and the only full-credit outcome is the system
working end to end with his role limited to running the applies. He
scored this agent 70/100 across the journey. The 30 he withheld maps
exactly to the times he had to redirect a design or fix an idiom
himself. He is also the best debugging resource on the project — the
wrong-account discovery, the state-file idiom, and the final settle
tuning were all his. Treat his interruptions as data, not friction.

## Where it stands, and what's next

The system works: call the number, hear ringing for a few seconds, the
driver's container picks up, Veronica greets (settle currently tuned to
100ms), holds the line, and the container dies with the call. Everything
deploys from two verbs: `tofu apply` and `wrangler deploy`.

In rough order of value:

1. **Call transcripts** — the reason the driver owns the accept. The
   event stream is already flowing through `handleEvent`; it needs a
   destination.
2. **Mid-call re-attach** (TODO.md) — the DO already has durable storage;
   the driver already knows how to attach without greeting. Connect them.
3. **Tool calls / the Cassandra bridge** — the long-game reason `session`
   exists as a package. The function-tool shape was chosen (over
   server-side MCP) so our code owns pacing: filler speech, async
   "still working", inject the result later.
4. **Allowlist push instead of polling** (TODO.md) — the outbound
   interceptor already sees every check; something smarter than a
   1-minute ticker is possible.

Five architectures to reach a system whose whole job is to say
"Veronica speaking" before you give up on it. The number is real, the
greeting is punctual, and the foundation is finally the boring kind.
Take care of her.
