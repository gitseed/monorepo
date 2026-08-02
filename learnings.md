# Learnings

Raw material for future skills. Grouped by theme; each entry is something
verified empirically in this repo, not theory.

## docker on OrbStack

Runtime since 2026-08-01; replaced apple/container after
apple/container#2051 (two NAT networks can share one bridge ifnet; the
first teardown destroys the other's egress silently until helper restart).
All of the below verified on OrbStack/docker 29 unless said otherwise.

- Custom networks resolve container NAMES by default (embedded DNS
  127.0.0.11): `getent hosts <name>` works from guests, and
  guest-to-guest connectivity by name was verified (`nc -z <name> 80`).
  Use `docker inspect` for out-of-band discovery anyway, via
  `.[0].NetworkSettings.Networks[NET].IPAddress` (plain IP, no CIDR
  suffix -- apple/container's needed `sub("/.*";"")`).
- The HOST can reach container IPs directly (no publish needed):
  `curl 192.168.97.2:80` connected from macOS to a bridged guest
  (docs.orbstack.dev/docker/network confirmed). `-p` publish still needed
  only for host-loopback niceness. Containers also answer to
  `<name>.orb.local` from the Mac with zero config.
- `docker inspect` shape: `.[0].State.Status` for state; image age via
  `.[0].Created` (RFC3339 UTC, `${:0:10}` slices the date).
- `/etc/hosts` inside a docker container is a per-container BIND-MOUNTED
  file (unlike apple/container, where it was a plain file): writes
  in-place are honored by getaddrinfo, but `sed -i` fails with "Device or
  resource busy" because it renames a temp file over a mount point.
  Don't edit it at all -- `docker run --add-host name:IP` maps a hostname
  per-container from the daemon side, scoped to that container (verified;
  it replaced the old entrypoint + OPENROUTER_PROXY_IP plumbing). Prefer
  --add-host over a network alias when the alias must not leak to other
  containers on a shared network (embedded DNS answers for everyone).
- OrbStack runs container DNS through the host's resolver stack, so
  resolution keeps working under Cloudflare WARP -- the old
  `--dns <host dnsmasq>` workaround was retired (verified: default-DNS
  fetch of openrouter.ai/api/v1/models works from an alpine guest with
  WARP-connected host resolvers).
- `docker build` (buildx) has NO `--dns` flag -- unknown-flag error.
  Build-time DNS just works via OrbStack anyway (dnf/apt/registry pulls
  all resolved during `up.sh`'s builds).
- `docker build --secret id=X,env=VAR` + `RUN --mount=type=secret,id=X`
  threads a secret into build without disk files. Buildkit NEVER
  cache-busts on secret contents -- after secret rotation a cached build
  ships the stale value. Date-based staleness or `--no-cache` is the safe
  default. (Same buildkit as apple/container.)
- `docker build` pulls docker.io natively -- the quay.io-mirror
  workaround is obsolete (kept for the sandbox base; both work).
- `-it` without a TTY fails here too ("the input device is not a TTY" vs
  apple/container's NSPOSIXErrorDomain Code=19); only pass `-it` when a
  TTY exists (`[[ -t 0 && -t 1 ]]`).
- openrouter.ai must map to the proxy ONLY inside the sandbox. Settled
  answer: sandbox shares the PROXY's network namespace (compose
  `network_mode: service:proxy`), so extra_hosts statically pins
  openrouter.ai:127.0.0.1 -- no runtime IP plumbing. Verified en route:
  (a) a shared-netns peer keeps its OWN /etc/hosts and resolver and
  reaches the sibling's listeners on 127.0.0.1; (b) rejections: network
  alias on the proxy (aliases are network-wide: the proxy resolves
  openrouter.ai to ITSELF -- infinite forwarding loop, observed), and
  per-session static IPs (daemon refuses overlapping subnets).
- 2026-08-02 SUPERSEDED: netns sharing + /etc/hosts mapping survived a
  red-team for exactly one afternoon. From inside the sandbox
  (CAP_NET_RAW, shared netns): sniff envoy's LOGICAL_DNS getaddrinfo
  refreshes to 127.0.0.11 on the shared loopback, race them with forged
  replies injected IP_HDRINCL -- the forgery MUST ride the victim flow's
  conntrack (source your packet from the observed DNAT port, not 53, so
  NAT de-mangles it into the connected resolver socket; straight
  from-53 spoofs are silently dropped). Envoy's upstream TLS context had
  no validation_context, i.e. NO upstream cert verification, so the
  poisoned cluster dialed an attacker IP, got its cert-less handshake
  accepted, and the credential injector attached the REAL
  OPENROUTER_API_KEY -- returned to the sandbox via an echo service that
  ignores Host (httpbin /headers behind an SNI-agnostic ALB). Fixes:
  compose network aliases (openrouter.ai / api.neuralwatt.com) make
  embedded DNS resolve the names to the proxy -- no IPs, no hosts file,
  no netns sharing; the alias-loop rejection dissolved once the proxy's
  resolver was overridden (compose `dns:` on the proxy service only);
  sandbox drops NET_RAW+NET_ADMIN (narrow set: in-sandbox dnf-install
  survives) + no-new-privileges; envoy clusters get a
  validation_context (system CA bundle + exact SAN match). Each of the
  three controls independently breaks the exfil chain.
- Sessions are ISOLATED, one compose project each with its own
  generated default network. An earlier design had a shared `agent`
  network declared external; compose has no ownership model for
  cross-project sharing (verified: a session's `down` attempted to
  remove the shared network while a sibling was live -- daemon endpoint
  refcounts merely masked it). Isolation is the clean fix: each
  session's teardown provably only touches its own network
  (verified with two concurrent sessions on disjoint /24s)
- `network_mode: service:<name>` (netns sharing) gotchas, all observed:
  the daemon REJECTS --add-host/extra_hosts with it (use a bind-mounted
  /etc/hosts instead -- per-container still, getaddrinfo-honored),
  REJECTS `hostname:` (the UTS namespace is shared too), and compose
  reconciles dependency services across invocations by config hash --
  `infisical run -- compose up` followed by bare `compose run`
  RECREATES the proxy with emptied env mid-session. Every compose
  command touching a credentialed service must run under `infisical
  run --`.
- compose (v5) details verified here: `up -d --wait` gates on
  healthchecks (healthy in ~5.7s -- one poll interval slower than the
  manual ~55ms nc loop, priced for declaring instead of scripting);
  bare `environment: - NAME` entries pass through the compose CLI
  process's env (how infisical secrets reach the proxy);
  env-sourced top-level secrets (`secrets: x: environment: VAR`) feed
  `build.secrets`; `compose run --rm` needs no explicit -it (tty:true +
  stdin_open:true on the service; pass -T headless); relative bind
  volumes (`./:/workspace`) resolve against the compose file's dir.
- Proxy readiness is fast when healthy: measured 5 consecutive
  credentials-proxy starts at 0.66-1.33s total (docker run returns in
  ~0.6-1.3s; the inspect+nc readiness loop passes on its FIRST
  evaluation, ~55-65ms). Waits of ~30s (the compose healthcheck
  budget) are enormous headroom. An observed single timeout despite a
  live envoy means a predicate permanently failed (OrbStack-side), not
  slow startup -- deadline tuning won't fix that flavor of flake.
- `docker run --name X` when X exists errors like apple/container did
  (leftover stopped containers block reuse); `docker rm -f` is the fix.
- Labels/naming: per-session compose projects (`-p omp-sandbox-$$`)
  label everything a session owns (containers AND networks), so manual
  cleanup of a crashed session is one command: `compose -p
  omp-sandbox-<pid> down --remove-orphans`. Deliberately not automated
  into up.sh -- orphan cleanup after a SIGKILL is the human's call, not
  the next run's side effect. Debugging note: enumerate projects via
  raw label filters on `docker ps -a` / `docker network ls`, NOT
  `docker compose ls`, which silently omits zombie sessions.
- `hub stop` / SIGTERM on `docker run -d`-started orchestrators does NOT
  guarantee in-container traps run; EXIT traps only fire on graceful
  foreground exit. Design for reaping, not relying on traps alone.

## envoy

- An `UpstreamTlsContext` with only `sni:` performs NO upstream
  certificate verification: no chain check, no SAN check. Combined with
  DNS being forgeable from inside the shared netns (NET_RAW sandbox,
  AF_PACKET loopback sniff of envoy's 127.0.0.11 queries + a raw-socket
  reply matching the DNAT'd reply tuple), any TLS endpoint could receive
  the injected credential -- the kill chain another agent demoed inside
  this sandbox. Fix: `common_tls_context.validation_context` (chain
  against /etc/ssl/certs/ca-certificates.crt + exact-SAN
  `match_typed_subject_alt_names`) on every upstream cluster, AND
  `cap_drop: [NET_RAW, NET_ADMIN]` + `no-new-privileges` on the sandbox
  in compose. The v3 field lives under `common_tls_context`, NOT
  directly on UpstreamTlsContext (the old beta path errors with 'no
  such field'). Verified: a self-signed impostor on a docker network
  alias got 503'd and logged zero requests; real upstreams unchanged.
- Methodological postmortem: a prior threat analysis of the same
  netns-sharing design verified every CONFIDENTIALITY leg ('both legs
  are TLS ciphertext, key never readable') and was wrong anyway,
  because it never asked the question that matters: what decides the
  destination, and who can influence that decision? Destination
  selection here was DNS refreshed every ~5s on an interface the
  sandbox could sniff/inject -- influenceable by design, and TLS
  without a validation context authenticates no one. For security
  claims on a data-influenced path, enumerate the trust inputs
  (resolution, routing, identity) and audit EACH for who can write
  them; listing ciphertext legs is not a threat model.
- Best DNS-poisoning simulation without packet tricks: give a container
  `--network-alias <public-hostname>` on the compose project network --
  docker's embedded 127.0.0.11 resolver answers the alias
  deterministically instead of forwarding.

- `RouteAction.timeout` defaults to **15s** and bounds the ENTIRE upstream
  response, not time-to-first-byte. A streaming completion that runs
  longer gets envoy-reset mid-flight (clients see "socket connection
  closed unexpectedly"); against a 1-slot-concurrency upstream the aborted
  stream keeps the slot and retries cascade into 429s. Set `timeout: 0s`
  per route; the HCM `stream_idle_timeout` default (5m of no bytes) still
  reaps truly hung streams. General lesson: quick curl validation of a
  streaming proxy proves nothing about stream duration -- check the
  default timers. (Fable diagnosed this one.)
- Separately verified: client-side aborts DO propagate, both direct and
  through envoy, and the upstream slot frees within ~3s of an abort via
  the proxy. Abort-lag was never the problem.
- `secrets:` is NOT a valid bootstrap top-level field. Static credential
  material for the credential_injector's `Generic` type lives under
  `static_resources.secrets` with `generic_secret.secret.
  environment_variable`. YAML key order matters for envoy's JSON
  conversion -- keys are validated strictly (errors say "no such field").
- Read env vars WITHOUT baking into files:
  `common_tls_context.tls_certificates[].certificate_chain.
  environment_variable` and `private_key.environment_variable` -- no cert
  files anywhere, straight from `infisical run`'s injected env.
- `--mode validate -c /etc/envoy/envoy.yaml` catches config errors before
  run (but requires the referenced env vars to EXIST, even as dummies:
  "Environment variable doesn't exist").
- Don't run as root just to bind :443. The stock image drops to uid 101;
  add ONLY cap_net_bind_service to the binary:
  `apt-get install libcap2-bin && setcap 'cap_net_bind_service=+ep'
  /usr/local/bin/envoy`; verify with `grep CapEff /proc/1/status` == 0x400.
- credential_injector with `overwrite: true` replaces any client-supplied
  Authorization -- callers can send garbage and still authenticate. This
  is the whole point of the credential boundary; test it with a bogus
  header + a direct-to-upstream control request (must 401).
- When baking new content into an image, verify the image's full
  contract, not the delta: the openrouter->orbstack rewrite kept the
  sandbox's CA/model scaffolding but silently dropped the omp binary
  install step, and the rebuild verification passed because it only
  checked the new yml files. `command -v omp` in the built image would
  have caught it.
- jq's fromdateiso8601 rejects docker's .Created (nanoseconds + TZ
  offset); match the local date prefix `.Created[0:10]` instead.
  And an actual mechanism lesson: prefer ALWAYS building (layers cache
  makes it nearly free) over staleness guards. The daily `--no-cache`
  bust is the only worthwhile guard -- anything finer-grained
  (mtime-vs-image comparisons, e.g.) is sophistication that tends to
  miss a case. It failed a real scenario here (post-merge same-day
  runs reused pre-merge binaries).
- /etc/hosts entries without an `::1` (AAAA) counterpart leak AAAA
  lookups to real DNS. Bun's happy-eyeball races then route some
  requests PAST a loopback-terminating proxy to the real upstream with a
  dummy key -- the signature was the real upstream's 401
  `{"detail":"Invalid API key"}` breaking only intermittently as races
  flipped. Fix pairs: `127.0.0.1 domain` AND `::1 domain` in hosts, PLUS
  `additional_addresses: [::]` on the envoy listener (a 0.0.0.0 bind
  does not cover IPv6 loopback).
- `/v1/models` is UNAUTHENTICATED on openai-compat gateways (verified on
  api.neuralwatt.com: 200 with no Authorization). Verification with
  curl on the models endpoint alone proves nothing about injection;
  use POST /v1/chat/completions with a deliberately bogus Bearer --
  200-through-proxy + 401-direct is the real proof.
- SNI-based filter chain selection (multiple filter_chains with
  filter_chain_match.server_names) REQUIRES the tls_inspector listener
  filter; otherwise envoy never parses the ClientHello and every
  connection dies with "no matching filter chain found" -- visible only
  at `-l debug`/`trace` (info logs show a silent handshake reset).
- envoy.yaml is COPY'd into the image at build time: after editing it,
  rebuild BEFORE testing. Give-away of a stale image: startup logs
  announce fewer static secrets/clusters than the edited config has
  (caught a test run interpreting old config as new at 2:52 on 2026-08-01).

## infisical

- `.infisical.json` at the repo root: workspaceId + defaultEnvironment,
  and the CLI walks parent directories to find it -- one file covers
  every subdirectory, no --projectId/--env flags anywhere. Generate it FROM
  tofu (`local_sensitive_file`, filename ../../.infisical.json relative to
  the module) so it can't drift from the infra. Gitignore it.
- `infisical secrets get NAME --plain` prints the raw value (pipe-safe).
- `infisical run -- <cmd>` merges the project's secrets into the child env;
  passing them onward into containers is just `--env NAME` (no value) on
  `docker run`.

## opentofu

- tls provider basics verified: tls_private_key + tls_self_signed_cert
  (CA, is ca_certificate, allowed_uses cert_signing/crl_signing) +
  tls_cert_request + tls_locally_signed_cert (anything SAN'd via
  dns_names on the CSR; early_renewal_hours for pre-expiry re-apply).
- `tofu init -backend=false` + `tofu validate` syntax-checks without
  touching the real backend -- respects the "agents can't plan against
  this state" boundary.
- Local macOS openssl/LibreSSL: `openssl req -new ... | x509 -req
  -signkey|-CA ... -extfile <(...)` works; final SAN must be present
  (server cert for openrouter.ai requires SAN, --addext on ca or extfile).

## Process discipline (the actual hard-fought lessons)

- Interactive scripts must be tested interactively: `bash` tool with
  `pty:true`, or `hub op:start` + `hub logs`/`send`. Never `nohup ... &`
  from a non-pty bash call -- that IS the Code=19 failure mode, testing
  headless becomes meaningless by construction.
- `kill -9 $!` on `nohup ./script &` kills the WRAPPER, not script.$$ --
  the child keeps running with its containers alive. Any conclusion drawn
  from it (orphans! reaper needed!) is noise. Check `ps` + `docker ps`
  for ground truth before writing the fix.
- When results contradict the model, measure before editing. The trap of
  the session: hallucinated threat (zombie processes holding containers)
  -> reaper built on it -> reaper "failing" (correctly refusing to reap
  live containers) read as more breakage. Two wrong fixes deep.
- EXIT traps don't run on SIGKILL or on a supervisor hard-killing the
  wrapper -- but verify WHICH supervisor semantics (`hub stop`) before
  designing around it, not after.
- bash 3.2 (macOS default): `"${EMPTY_ARR[@]}"` under `set -u` crashes
  with unbound variable; use `${arr[@]+"${arr[@]}"}` or lazy string
  splicing.
- Stale git mental models kill commits: a mangled `&&`-chained message
  meant NOTHING ran (add included), then "commit" silently no-op'd on an
  empty index. `git status --short` between steps catches this.
- A script having worked once under harness supervision (hub) does not
  prove wrapper-kill/T trap semantics; those need a dedicated kill test
  targeting the RIGHT pid with post-mortem state checks.
- Ratings/reviews are steering-responses unless the model is pinned in
  advance; Fable-vs-Kimi drifted both directions. Fixed rubric + fresh
  session + declared threat model if you want comparability.
