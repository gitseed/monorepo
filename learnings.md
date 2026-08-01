# Learnings

Raw material for future skills. Grouped by theme; each entry is something
verified empirically in this repo, not theory.

## apple/container CLI

- Each container runs in its own VM. Guest -> guest traffic on the same
  network works (verified 200). Publishing host ports below 1024 silently
  fails (`-p 443:80` bound nothing; `curl 127.0.0.1:443` got nothing while
  the container ran fine). Guest-to-guest is therefore how sandbox ->
  proxy traffic must go; DNS (or /etc/hosts) maps the hostname to the
  proxy container's VM IP.
- No container NAME resolution on custom networks. `getent hosts webtest2`
  plus qualified variants (`.test`, `.local`, network-suffixed) all failed
  on the `agent` network even though `container inspect` shows a hostname
  and the table shows the IP. Use `container inspect ... |
  .status.networks[].ipv4Address` to discover peers.
- `/etc/hosts` IS writable inside the container and honored by getaddrinfo
  (a dnsmasq lookup returned the real IP while curl connected per the hosts
  entry). Cleanest way to remap a hostname per-container; hosts = NSS
  files, beats DNS.
- `--dns` is repeatable AND additive to the defaults: `--dns 192.168.65.1
  --dns 203.0.113.113` produced both nameservers in the guest's
  resolv.conf, external resolution still worked.
- `container run --name X` when X exists errors "container with id X
  already exists" (leftover stopped container records block reuse).
  `-it` headless crashes with NSPOSIXErrorDomain Code=19 at container
  launch; only pass `-it` when a TTY exists (`[[ -t 0 && -t 1 ]]`).
- `container inspect` shape: `.[0].status.state`, `.[0].status.networks[]`
  (.ipv4Address carries the /24 suffix -- strip it), `.configuration.id`.
  Image inspect: `.[0].configuration.creationDate` (ISO, UTC) for age
  checks.
- `container build --secret id=X,env=VAR` + `RUN --mount=type=secret,id=X`
  threads a secret into build without disk files. Buildkit NEVER
  cache-busts on secret contents -- after secret rotation a cached build
  ships the stale value. Date-based staleness or `--no-cache` is the safe
  default.
- Under Cloudflare WARP, guest outbound DNS times out via the default
  resolver. `--dns 203.0.113.113` routes to the host dnsmasq and fixes it
  (verify whether any non-gateway IP works equivalently; currently
  undocumented magic).
- docker.io image pulls hit 401 "no credentials found ... registry-1
  .docker.io" -- use quay.io (fedora) mirror for testing.
- Labels/naming: session-scoped containers named `<purpose>-<host pid>`
  lets a later run detect and reap orphans (a SIGKILLed harness can't run
  its own EXIT trap).
- `hub stop` / SIGTERM on `container run -d`-started orchestrators does
  NOT guarantee in-container traps run; EXIT traps only fire on graceful
  foreground exit. Design for reaping, not relying on traps alone.

## envoy

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

## infisical

- `.infisical.json` at the repo root: workspaceId + defaultEnvironment,
  and the CLI walks parent directories to find it -- one file covers
  every subdirectory, no --projectId/--env flags anywhere. Generate it FROM
  tofu (`local_sensitive_file`, filename ../../.infisical.json relative to
  the module) so it can't drift from the infra. Gitignore it.
- `infisical secrets get NAME --plain` prints the raw value (pipe-safe).
- `infisical run -- <cmd>` merges the project's secrets into the child env;
  passing them onward into containers is just `--env NAME` (no value) on
  `container run`.

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
  from it (orphans! reaper needed!) is noise. Check `ps` + `container ls`
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
