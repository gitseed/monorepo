// Morph Fast Apply extension for OMP.
// Calls morph-v3-fast via OpenRouter to merge partial code edits into files.
// The model provides an instruction + a lazy edit snippet (using
// `// ... existing code ...` markers), and Morph returns the complete merged file.
//
// Requires: OPENROUTER_API_KEY env var (set by the sandbox; the credentials
// proxy injects the real key). Override the model with MORPH_MODEL.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent"
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from "node:fs"
import { resolve, isAbsolute, join } from "node:path"
import { tmpdir } from "node:os"

const MORPH_MODEL = process.env.MORPH_MODEL || "morph/morph-v3-fast"
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
// Morph v3-fast has an 82K token context; 70K bytes is a conservative limit
// leaving room for the instruction, update snippet, and response tokens.
const MAX_FILE_BYTES = 70_000

export default function (pi: ExtensionAPI) {
  const type = pi.arktype

  // Standalone const: registerTool only narrows execute params when the
  // schema is a resolved type, not an inline generic call.
  const editParams = type({
    path: type("string").describe("Path to the file to edit"),
    instruction: type("string").describe("First-person description of what you're changing"),
    update: type("string").describe("Partial edit: only changed code with `// ... existing code ...` markers"),
  })

  pi.registerTool({
    name: "edit",
    label: "Edit",
    description: [
      "Apply a code edit using Morph Fast Apply via OpenRouter.",
      "",
      "Sends the file content and a partial edit snippet to morph-v3-fast,",
      "which merges them and returns the complete file. You don't need exact",
      "line numbers or to reproduce unchanged code.",
      "",
      "Parameters:",
      "- path: File to edit (relative to workspace root or absolute)",
      "- instruction: First-person description of the change (e.g. 'Adding",
      "  error handling to the auth flow')",
      "- update: ONLY the changed code regions, using `// ... existing code",
      "  ...` markers for unchanged sections between them. The marker syntax",
      "  works for any file type (YAML, Python, TS, etc).",
      "",
      "Example update:",
      "  // ... existing code ...",
      "  if (!user) throw new Error('User not found')",
      "  // ... existing code ...",
      "",
      "Prefer this tool for config files (YAML/TOML/JSON), large structural",
      "edits, or multi-region changes where line-anchoring is fragile.",
    ].join("\n"),
    parameters: editParams,
    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      const filePath = isAbsolute(params.path)
        ? params.path
        : resolve(ctx.cwd, params.path)

      let oldContent: string
      try {
        oldContent = readFileSync(filePath, "utf-8")
      } catch (err) {
        return {
          content: [{ type: "text", text: `Error reading ${params.path}: ${err instanceof Error ? err.message : String(err)}` }],
          isError: true,
        }
      }

      // Guard against files too large for Morph's context window.
      if (Buffer.byteLength(oldContent) > MAX_FILE_BYTES) {
        return {
          content: [{
            type: "text",
            text: `Error: file is ${Buffer.byteLength(oldContent)} bytes, exceeds Morph limit of ${MAX_FILE_BYTES}. Use the built-in edit tool instead.`,
          }],
          isError: true,
        }
      }

      onUpdate?.({ content: [{ type: "text", text: `Merging via ${MORPH_MODEL}...` }] })

      const prompt =
        `<instruction>${params.instruction}</instruction>\n` +
        `<code>${oldContent}</code>\n` +
        `<update>${params.update}</update>`

      let response: Response
      try {
        response = await fetch(OPENROUTER_URL, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${process.env.OPENROUTER_API_KEY}`,
            "Content-Type": "application/json",
            "HTTP-Referer": "https://github.com/gitseed/monorepo",
            "X-Title": "OMP Morph Extension",
          },
          body: JSON.stringify({
            model: MORPH_MODEL,
            messages: [{ role: "user", content: prompt }],
          }),
          signal: signal ?? undefined,
        })
      } catch (err) {
        if (signal?.aborted) {
          return { content: [{ type: "text", text: "Cancelled" }] }
        }
        return {
          content: [{ type: "text", text: `Network error calling Morph: ${err}` }],
          isError: true,
        }
      }

      if (!response.ok) {
        const errBody = await response.text().catch(() => response.statusText)
        return {
          content: [{ type: "text", text: `Morph API error (${response.status}): ${errBody}` }],
          isError: true,
        }
      }

      let data: { choices?: Array<{ message?: { content?: string }; finish_reason?: string }> }
      try {
        data = (await response.json()) as typeof data
      } catch (err) {
        return {
          content: [{ type: "text", text: `Error parsing Morph response: ${err instanceof Error ? err.message : String(err)}` }],
          isError: true,
        }
      }

      const choice = data.choices?.[0]
      const newContent = choice?.message?.content

      if (!newContent || typeof newContent !== "string") {
        return {
          content: [{ type: "text", text: "Error: Morph returned no content" }],
          isError: true,
        }
      }

      // Guard against truncated output — never write a partial file.
      if (choice?.finish_reason !== "stop") {
        return {
          content: [{ type: "text", text: `Error: Morph output was truncated (finish_reason: ${choice?.finish_reason ?? "unknown"}). File left unchanged.` }],
          isError: true,
        }
      }

      // Defense in depth: some models wrap output in markdown fences.
      const stripped = newContent.replace(/^```[\w]*\n?/, "").replace(/\n?```$/, "")
      if (stripped !== newContent) {
        return {
          content: [{ type: "text", text: `Error: Morph output contains markdown fences. File left unchanged. Raw output:\n${newContent.slice(0, 500)}` }],
          isError: true,
        }
      }

      if (newContent === oldContent) {
        return {
          content: [{ type: "text", text: `No changes — Morph returned identical content for ${params.path}.` }],
        }
      }

      writeFileSync(filePath, newContent)

      const diffDir = mkdtempSync(join(tmpdir(), "morph-diff-"))
      const oldCopy = join(diffDir, "original")
      try {
        writeFileSync(oldCopy, oldContent)
        const diffResult = await pi.exec(
          "diff",
          ["-u", "--label", params.path, "--label", params.path, oldCopy, filePath],
          { signal },
        )
        // diff exits 0 when identical, 1 when different — both are fine.
        const diffText =
          diffResult.code === 0
            ? "(no differences)"
            : diffResult.stdout || "(no diff output)"

        return {
          content: [{ type: "text", text: `Edited ${params.path}:\n\n${diffText}` }],
          details: { path: params.path, model: MORPH_MODEL },
        }
      } finally {
        rmSync(diffDir, { recursive: true, force: true })
      }
    },
  })
}
