# Sandbox usability — prioritized TODO

Ranked top-to-bottom by leverage: each item unblocks what sits below it.

## P0 — unblocks everything else

1. **Persist the agent brain (`~/.omp`) on a named volume**
   - `compose.yml`: mount `omp-agent:/root/.omp`; top-level `volumes:
     omp-agent: {external: true}` (external so it is not re-scoped per run by
     the `$$` project name).
   - `scripts/up.bash`: `docker volume create omp-agent` (idempotent). Created
     empty once; the image's baked `config.yml`/`natives/` populate it on first
     mount, no seed step needed.
   - Without this, memory, history, and session state die on every teardown
     and daily rebuild (`memory.backend: local` makes it worse). Nothing else
     matters if the agent forgets the project every morning.

2. **Fix the runtime mismatch: real Node 22 + npm, keep bun as `bun`**
   - `container/sandbox.containerfile`: `node` today is a bun alias and `npm`
     is absent, so every npm/wrangler/`package-lock` path breaks. Install Node
     22 LTS + npm as `node`; stop aliasing `node -> bun`. Keep bun under its
     own name for the harness.

3. **Install the infra toolchain, pinned**
   - `container/sandbox.containerfile`: OpenTofu `1.12.3`, Go, gcloud, gh —
     each version/sha-pinned like bun already is. This is what makes
     "I prepare, you apply" possible (tofu plan, go vet/test, gcloud builds).

## P1 — daily work ergonomics

4. **Git identity + GitHub auth wired in**
   - Identity injected from env at build (not baked), `safe.directory=/workspace`
     preset, and a working `gh`/ssh path so the container can clone this
     ecosystem and push results.

5. **Bash ergonomics (`.bashrc.d`)**
   - Prompt marking sandbox + workspace, sane `HIST`, aliases, default
     `cd /workspace`.

## P2 — hardening the setup

6. **Align `agent-config.yml` with persistence + method**
   - Confirm `memory.backend` points at the persisted volume; keep high
     thinking; defaults that assume the validate-then-hand-off loop.

7. **A usability smoke/canary test**
   - Boot the sandbox and assert `node -v`, `npm --version`, `tofu version`,
     `go version`, `gh --version` all return, so a future image change that
     reintroduces a bun-shim/no-npm regression fails loudly.

---

Status: `1` in progress. Doing one item at a time.
