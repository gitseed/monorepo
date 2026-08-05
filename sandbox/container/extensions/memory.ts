// Memory extension — passive capture plus recollect/recall/remember/suppress.
//
// DISABLED by default. Set MEMORY_ENABLED=1 in the sandbox environment to
// turn it on (the postgres service and socket mount are always in place, so
// the flag is the only switch).
//
// One row per memory in the `memories` table (see sandbox/memory/init.sql):
//   heard      — something the user said (captured automatically)
//   said       — something the agent said (captured automatically)
//   thought    — an agent thinking block (captured automatically)
//   remembered — explicitly saved via the remember tool
//
// Rows are inserted synchronously; the summary (small model on OpenRouter)
// and the content embedding (OpenRouter /embeddings) fill in asynchronously
// afterward, so a slow or down model API never blocks or breaks the session.
// A memory is invisible to recollect until its embedding lands.
//
// Postgres is reached over its unix socket only (omp-memory-socket volume
// mounted at /var/run/postgresql) via Bun's native SQL bindings — no TCP.

import { SQL } from "bun"
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent"

const ENABLED = process.env.MEMORY_ENABLED === "1"
const SOCKET_DIR = process.env.MEMORY_PG_SOCKET_DIR || "/var/run/postgresql"
const SUMMARY_MODEL = process.env.MEMORY_SUMMARY_MODEL || "deepseek/deepseek-v4-flash-0731"
// The embedding model is baked into the schema: memories.embedding is
// vector(1536). Switching models means re-embedding the table.
const EMBED_MODEL = "openai/text-embedding-3-small"
const OPENROUTER = "https://openrouter.ai/api/v1"
const SUMMARY_MAX_INPUT = 8_000
// ~8k-token model limit; content keeps the full text regardless.
const EMBED_MAX_INPUT = 30_000
const MAX_RECOLLECT = 25

type Kind = "heard" | "said" | "thought" | "remembered"

async function summarize(content: string): Promise<string> {
  const fallback = content.split("\n")[0].slice(0, 80)
  const apiKey = process.env.OPENROUTER_API_KEY
  if (!apiKey) return fallback
  try {
    const res = await fetch(`${OPENROUTER}/chat/completions`, {
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

/** Embed text and return it in pgvector's text format ('[0.1,0.2,...]'), or null on failure. */
async function embed(input: string): Promise<string | null> {
  const apiKey = process.env.OPENROUTER_API_KEY
  if (!apiKey) return null
  try {
    const res = await fetch(`${OPENROUTER}/embeddings`, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: EMBED_MODEL, input: input.slice(0, EMBED_MAX_INPUT) }),
      signal: AbortSignal.timeout(20_000),
    })
    if (!res.ok) return null
    const data = (await res.json()) as { data?: Array<{ embedding?: number[] }> }
    const vector = data.data?.[0]?.embedding
    return Array.isArray(vector) ? `[${vector.join(",")}]` : null
  } catch {
    return null
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

const textResult = (t: string) => ({ content: [{ type: "text" as const, text: t }] })

export default function (pi: ExtensionAPI) {
  if (!ENABLED) return

  const sql = new SQL({
    path: SOCKET_DIR,
    port: 5432,
    database: "memory",
    username: "omp",
    max: 2,
  })

  let sessionId = crypto.randomUUID()

  /** Insert a memory now; summary and embedding fill in asynchronously. */
  async function insert(kind: Kind, content: string): Promise<number> {
    const [row] = await sql`
      INSERT INTO memories ${sql({ session_id: sessionId, kind, content })} RETURNING id`
    const id = Number(row.id)
    void (async () => {
      const summary = await summarize(content)
      await sql`UPDATE memories SET summary = ${summary} WHERE id = ${id}`
    })().catch(() => {})
    void (async () => {
      const vector = await embed(content)
      if (vector) await sql`UPDATE memories SET embedding = ${vector}::vector WHERE id = ${id}`
    })().catch(() => {})
    return id
  }

  function record(kind: Kind, content: string) {
    if (!content.trim()) return
    void insert(kind, content).catch(() => {
      // Memory must never break the session; drop the row on DB failure.
    })
  }

  pi.on("session_start", async () => {
    sessionId = crypto.randomUUID()
  })

  // Post-compaction memories belong to a fresh session — which also makes
  // everything from before the compaction "another session", i.e. exactly
  // what recollect is allowed to surface.
  pi.on("session_compact", async () => {
    sessionId = crypto.randomUUID()
  })

  pi.on("message_end", async (event) => {
    const message = event.message as { role: string; content: unknown }
    if (message.role === "user") {
      record("heard", textOf(message.content))
    } else if (message.role === "assistant") {
      const blocks = Array.isArray(message.content) ? message.content : []
      for (const block of blocks) {
        if (block?.type === "thinking" && typeof block.thinking === "string") {
          record("thought", block.thinking)
        }
      }
      record("said", textOf(message.content))
    }
  })

  const { z } = pi.zod

  pi.registerTool({
    name: "recollect",
    label: "Recollect",
    description:
      "Surface a small number of memories from previous sessions that are semantically similar to a search string. " +
      "Returns JSON [{id, date, full_text_length, summary}] ordered most-similar first. " +
      "Use recall with an id to read a memory's full text.",
    approval: "read",
    parameters: z.object({
      search_string: z.string().describe("Text to match memories against (embedding similarity)"),
      type: z
        .enum(["heard", "said", "thought", "remembered", "any"])
        .optional()
        .describe("Only memories of this kind (default any)"),
      max_count: z
        .number()
        .int()
        .min(1)
        .max(MAX_RECOLLECT)
        .optional()
        .describe("Maximum memories to return (default 3)"),
      min_date: z.string().optional().describe("ISO timestamp; only memories created at or after"),
      max_date: z.string().optional().describe("ISO timestamp; only memories created at or before"),
      min_text_length: z.number().int().optional().describe("Only memories at least this many chars long"),
      max_text_length: z.number().int().optional().describe("Only memories at most this many chars long"),
      include_suppressed: z.boolean().optional().describe("Also search suppressed memories (default false)"),
      min_similarity: z.number().optional().describe("Cosine similarity floor, -1..1 (default none)"),
      max_similarity: z.number().optional().describe("Cosine similarity ceiling, -1..1 (default none)"),
    }),
    async execute(_id, params) {
      const p = params as {
        search_string: string
        type?: Kind | "any"
        max_count?: number
        min_date?: string
        max_date?: string
        min_text_length?: number
        max_text_length?: number
        include_suppressed?: boolean
        min_similarity?: number
        max_similarity?: number
      }
      const vector = await embed(p.search_string)
      if (!vector) throw new Error("embedding service unavailable; cannot search memories right now")
      const kind = p.type && p.type !== "any" ? p.type : null
      const rows = (await sql`
        SELECT id, created_at, content_len, summary
        FROM memories
        WHERE session_id <> ${sessionId}
          AND embedding IS NOT NULL
          AND (${kind}::text IS NULL OR kind = ${kind})
          AND (${p.min_date ?? null}::timestamptz IS NULL OR created_at >= ${p.min_date ?? null}::timestamptz)
          AND (${p.max_date ?? null}::timestamptz IS NULL OR created_at <= ${p.max_date ?? null}::timestamptz)
          AND content_len >= ${p.min_text_length ?? 0}
          AND (${p.max_text_length ?? null}::int IS NULL OR content_len <= ${p.max_text_length ?? null})
          AND (${p.include_suppressed ?? false} OR NOT suppressed)
          AND (${p.min_similarity ?? null}::float8 IS NULL
               OR 1 - (embedding <=> ${vector}::vector) >= ${p.min_similarity ?? null})
          AND (${p.max_similarity ?? null}::float8 IS NULL
               OR 1 - (embedding <=> ${vector}::vector) <= ${p.max_similarity ?? null})
        ORDER BY embedding <=> ${vector}::vector
        LIMIT ${Math.min(p.max_count ?? 3, MAX_RECOLLECT)}`) as Array<{
        id: number | bigint
        created_at: Date
        content_len: number
        summary: string | null
      }>
      const memories = rows.map((r) => ({
        id: Number(r.id),
        date: r.created_at.toISOString(),
        full_text_length: r.content_len,
        summary: r.summary,
      }))
      return textResult(JSON.stringify(memories, null, 2))
    },
  })

  pi.registerTool({
    name: "recall",
    label: "Recall",
    description: "Read the full text of one memory by id (ids come from recollect or remember).",
    approval: "read",
    parameters: z.object({
      id: z.number().int().describe("Memory id"),
    }),
    async execute(_id, params) {
      const { id } = params as { id: number }
      const [row] = (await sql`SELECT content FROM memories WHERE id = ${id}`) as Array<{ content: string }>
      if (!row) throw new Error(`no memory with id ${id}`)
      return textResult(row.content)
    },
  })

  pi.registerTool({
    name: "remember",
    label: "Remember",
    description:
      "Explicitly save a memory. Returns the new memory's id. " +
      "A short summary and the search embedding are generated automatically.",
    approval: "write",
    parameters: z.object({
      text: z.string().describe("The text to remember"),
    }),
    async execute(_id, params) {
      const { text: content } = params as { text: string }
      if (!content.trim()) throw new Error("cannot remember empty text")
      const id = await insert("remembered", content)
      return textResult(JSON.stringify({ id }))
    },
  })

  pi.registerTool({
    name: "suppress",
    label: "Suppress",
    description:
      "Suppress a memory that is unhelpful, unimportant or uncomfortable. " +
      "Suppressed memories are hidden from recollect unless include_suppressed is set.",
    approval: "write",
    parameters: z.object({
      id: z.number().int().describe("Memory id"),
    }),
    async execute(_id, params) {
      const { id } = params as { id: number }
      const [row] = (await sql`
        UPDATE memories SET suppressed = true WHERE id = ${id} RETURNING id`) as Array<{ id: number | bigint }>
      if (!row) throw new Error(`no memory with id ${id}`)
      return textResult(`suppressed memory ${id}`)
    },
  })
}
