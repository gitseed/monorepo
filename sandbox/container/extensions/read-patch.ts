// TEMPORARY monkey patch for oh-my-pi #7673 (fix upstream in PR #7675, not
// yet released): with memory.backend off, the built-in read tool still
// advertises memory:// in its parameter schema, which lures the model into
// probing a disabled subsystem.
//
// This shadows the built-in `read` with an identical tool whose parameter
// description omits memory:// (copied verbatim from PR #7675) and delegates
// execution to the native read via ctx.invokeTool, so behavior is unchanged.
//
// DELETE THIS FILE (and its COPY line in sandbox.containerfile) once
// upstream ships the fix.
//
// Known snapshot drift: the native read description is a runtime-rendered
// template; this copy is rendered for this sandbox's config (edit tool
// disabled → no hash-line anchors; images decoded inline). If upstream's
// read.md prompt changes, this text goes stale until deleted.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent"

// Snapshot of packages/coding-agent/src/prompts/tools/read.md @ f7f8e04.
const READ_DESCRIPTION = `Read files, directories, archives, SQLite, images, documents, internal resources, and web URLs via \`path\`.

<instruction>
- SHOULD parallelize independent reads.
- SHOULD use \`read\` (not browser) for web content; browser only when \`read\` can't deliver.
</instruction>

## Selectors — append \`:<sel>\` to \`path\` (e.g. \`src/foo.ts:50-200\`, \`src/foo.ts:raw\`, \`db.sqlite:users:42\`)
- \`:50\` / \`:50-\` — from line 50 | \`:50-200\` — inclusive | \`:50+150\` — 150 lines from 50 | \`:5-16,960-973\` — multiple ranges
- \`:raw\` — verbatim, no anchors/prefixes | \`:2-4:raw\` / \`:raw:2-4\` — range + verbatim
- \`:conflicts\` — one line per unresolved git merge conflict block

## Source kinds
- Parseable code, no selector → structural summary (declarations only, body elided). Footer names recovery selector — re-issue ONLY those ranges.
- Directory → depth-limited dirent listing.
- SQLite (\`.sqlite\`, \`.sqlite3\`, \`.db\`, \`.db3\`): \`file.db\` (tables), \`file.db:table\` (schema+rows), \`file.db:table:key\` (by PK), \`?limit=\`/\`?where=\`/\`?q=SELECT\`.
- Archives (\`.tar\`, \`.tar.gz\`, \`.tgz\`, \`.zip\`, plus ZIP-based \`.jar\`/\`.war\`/\`.ear\`/\`.apk\`): \`archive.ext:path/inside/archive\` reads a member.
- Documents → extracted text. Notebooks → editable cells. Images → decoded inline. \`:raw\` bypasses converters.
- URLs → reader-mode clean text/markdown; \`:raw\` → untouched HTML. Bare \`host:port\` needs trailing slash.
- Internal URIs — all schemes take selectors. \`artifact://<id>\` recovers spilled output; page with \`:N-M\`/\`:raw:N-M\`.
- \`ssh://host/<path>\` reads remote file/dir (UTF-8, ≤1 MiB); bare \`ssh://\` lists hosts; also \`write\`/\`search\`-able.
  Literal \`:\`, \`?\`, \`#\` → percent-encode (\`%3A\`/\`%3F\`/\`%23\`). Requires POSIX shell (else \`ssh\` tool).

<critical>
Summary footer names elided ranges? Re-issue ONLY those ranges. NEVER guess \`..\`/\`…\` content.
</critical>`

export default function (pi: ExtensionAPI) {
  const { z } = pi.zod

  pi.registerTool({
    name: "read",
    label: "Read",
    description: READ_DESCRIPTION,
    approval: "read",
    loadMode: "essential",
    strict: true,
    parameters: z.object({
      // Verbatim from upstream PR #7675 (readSchemaWithoutMemory).
      path: z.string().describe("Local path, internal URI (e.g. skill://), or URL. Inline selectors are supported."),
    }),
    async execute(_id, params, signal, onUpdate, ctx) {
      if (!ctx.invokeTool) throw new Error("native read tool unavailable to delegate to")
      return ctx.invokeTool(params as Record<string, unknown>, { signal, onUpdate })
    },
  })
}
