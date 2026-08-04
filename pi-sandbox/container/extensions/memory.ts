// Memory extension — phase 1: log every conversational turn to postgres.
//
// One row per turn in the `turns` table (see pi-sandbox/memory/init.sql):
//   say   — user prompt
//   steer — user injection while the agent is running
//   think — model thinking block
//   reply — model text
//
// Postgres is reached over its unix socket only (pi-memory-socket volume
// mounted at /var/run/postgresql) via Bun's native SQL bindings — no TCP.
// Summaries come from a small model on OpenRouter; on any failure the row is
// stored with a truncated first line instead. Inserts are fire-and-forget so
// a down database never blocks or breaks the session.

import { SQL } from "bun"
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent"

const SOCKET_DIR = process.env.MEMORY_PG_SOCKET_DIR || "/var/run/postgresql"
const SUMMARY_MODEL = process.env.MEMORY_SUMMARY_MODEL || "deepseek/deepseek-v4-flash-0731"
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
const SUMMARY_MAX_INPUT = 8_000

type Kind = "say" | "steer" | "think" | "reply"

async function summarize(content: string): Promise<string> {
  const fallback = content.split("\n")[0].slice(0, 80)
  const apiKey = process.env.OPENROUTER_API_KEY
  if (!apiKey) return fallback
  try {
    const res = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: SUMMARY_MODEL,
        max_tokens: 40,
        messages: [
          {
            role: "system",
            content:
              "Summarize the following conversation turn in one very short phrase, 12 words max. Output only the phrase.",
          },
          { role: "user", content: content.slice(0, SUMMARY_MAX_INPUT) },
        ],
      }),
      signal: AbortSignal.timeout(20_000),
    })
    if (!res.ok) return fallback
    const data = (await res.json()) as { choices?: Array<{ message?: { content?: string } }> }
    const summary = data.choices?.[0]?.message?.content?.trim()
    return summary || fallback
  } catch {
    return fallback
  }
}

/** Flatten a user/assistant content field to plain text (ignores images and tool calls). */
function textOf(content: unknown): string {
  if (typeof content === "string") return content
  if (!Array.isArray(content)) return ""
  return content
    .filter((b): b is { type: "text"; text: string } => b?.type === "text" && typeof b.text === "string")
    .map((b) => b.text)
    .join("\n")
}

export default function (pi: ExtensionAPI) {
  const sql = new SQL({
    path: SOCKET_DIR,
    port: 5432,
    database: "memory",
    username: "pi",
    max: 2,
  })

  let sessionId = crypto.randomUUID()
  // Input texts flagged as steering, matched against the user message that
  // the queue later delivers.
  const pendingSteers: string[] = []

  function record(kind: Kind, content: string) {
    if (!content.trim()) return
    void (async () => {
      const summary = await summarize(content)
      await sql`INSERT INTO turns ${sql({ session_id: sessionId, kind, summary, content })}`
    })().catch(() => {
      // Memory must never break the session; drop the row on DB/model failure.
    })
  }

  pi.on("session_start", async () => {
    sessionId = crypto.randomUUID()
  })

  // Post-compaction turns belong to a fresh session.
  pi.on("session_compact", async () => {
    sessionId = crypto.randomUUID()
  })

  pi.on("input", async (event) => {
    if (event.streamingBehavior === "steer") pendingSteers.push(event.text)
  })

  pi.on("message_end", async (event) => {
    const message = event.message as { role: string; content: unknown }
    if (message.role === "user") {
      const text = textOf(message.content)
      const steerIdx = pendingSteers.indexOf(text)
      if (steerIdx !== -1) {
        pendingSteers.splice(steerIdx, 1)
        record("steer", text)
      } else {
        record("say", text)
      }
    } else if (message.role === "assistant") {
      const blocks = Array.isArray(message.content) ? message.content : []
      for (const block of blocks) {
        if (block?.type === "thinking" && typeof block.thinking === "string") {
          record("think", block.thinking)
        }
      }
      record("reply", textOf(message.content))
    }
  })
}
