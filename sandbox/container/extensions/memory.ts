// Memory extension — passive capture, recollect/recall/remember/suppress
// tools, and unprompted surfacing.
//
// Configured by /root/.omp/agent/memory.json (override the path with
// MEMORY_CONFIG); missing file or keys fall back to DEFAULTS below, with
// enabled=false, so the extension is inert until the config turns it on.
// OPENROUTER_API_KEY stays an env var — it's a secret, not config.
//
// One row per memory in the `memories` table (see sandbox/memory/init.sql):
//   heard      — something the user said (captured automatically)
//   said       — something the agent said (captured automatically)
//   thought    — an agent thinking block (captured automatically)
//   remembered — explicitly saved via the remember tool
//
// Captured content is embedded first, then inserted with its vector; the
// summary backfills asynchronously. On failure the column stays NULL —
// failures stay visible, nothing is fabricated. A memory is invisible to
// recollect and surfacing until its embedding lands.
//
// Unprompted surfacing (surfacing.enabled): every heard/said/thought event
// reuses the vector already computed for the write to run four per-kind
// similarity queries against other sessions, and injects the hits as a
// <recollected> block (see APPEND_SYSTEM.md for the model-facing contract).
// Injections are custom-role messages, so capture can never see them:
// surfaced memories must not become memories. Delivery never elicits a
// response: heard surfaces pre-run via before_agent_start (the prompt
// embed blocks ~300ms, then the block is in context before the model
// responds); recall chaining rides the recall tool result; said/thought/
// steered input queue as nextTurn context seen alongside the next real
// message. Each memory surfaces at most once per session (cooldown).
//
// Postgres is reached over its unix socket only (omp-memory-socket volume)
// via Bun's native SQL bindings — no TCP.

import { SQL } from "bun"
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent"
import { Text } from "@oh-my-pi/pi-tui"

const CONFIG_PATH = process.env.MEMORY_CONFIG || "/root/.omp/agent/memory.json"
const OPENROUTER = "https://openrouter.ai/api/v1"
const SURFACING_MESSAGE_TYPE = "memory-recollection"

interface MemoryConfig {
  enabled: boolean
  postgres: {
    socketPath: string
    port: number
    database: string
    username: string
    maxConnections: number
  }
  summary: {
    model: string
    maxInputChars: number
    maxTokens: number
    timeoutMs: number
  }
  embedding: {
    // Baked into the schema: memories.embedding is vector(1536).
    // Switching models means re-embedding the table.
    model: string
    maxInputChars: number
    timeoutMs: number
  }
  recollect: {
    defaultCount: number
    maxCount: number
  }
  surfacing: {
    enabled: boolean
    minSimilarity: number
    maxSimilarity: number
    perKindLimit: number
  }
}

const DEFAULTS: MemoryConfig = {
  enabled: false,
  postgres: {
    socketPath: "/var/run/postgresql",
    port: 5432,
    database: "memory",
    username: "omp",
    maxConnections: 2,
  },
  summary: {
    model: "deepseek/deepseek-v4-flash-0731",
    maxInputChars: 8_000,
    maxTokens: 40,
    timeoutMs: 20_000,
  },
  embedding: {
    model: "openai/text-embedding-3-small",
    maxInputChars: 30_000,
    timeoutMs: 20_000,
  },
  recollect: {
    defaultCount: 3,
    maxCount: 25,
  },
  surfacing: {
    enabled: false,
    // min gates relevance; max is the anti-déjà-vu filter — near-identical
    // memories (the same exchange from a past session) don't resurface.
    minSimilarity: 0.55,
    maxSimilarity: 0.95,
    perKindLimit: 2,
  },
}

async function loadConfig(): Promise<MemoryConfig> {
  try {
    const raw = (await Bun.file(CONFIG_PATH).json()) as Partial<MemoryConfig>
    return {
      enabled: raw.enabled ?? DEFAULTS.enabled,
      postgres: { ...DEFAULTS.postgres, ...raw.postgres },
      summary: { ...DEFAULTS.summary, ...raw.summary },
      embedding: { ...DEFAULTS.embedding, ...raw.embedding },
      recollect: { ...DEFAULTS.recollect, ...raw.recollect },
      surfacing: { ...DEFAULTS.surfacing, ...raw.surfacing },
    }
  } catch {
    return DEFAULTS
  }
}

type Kind = "heard" | "said" | "thought" | "remembered"
const KINDS: Kind[] = ["heard", "said", "thought", "remembered"]

/** One-phrase summary from the summary model, or null on any failure. No
 *  fabricated stand-ins: a NULL summary column is the loud, queryable
 *  signal that summarization failed or hasn't run. */
async function summarize(cfg: MemoryConfig["summary"], content: string): Promise<string | null> {
  const apiKey = process.env.OPENROUTER_API_KEY
  if (!apiKey) return null
  try {
    const res = await fetch(`${OPENROUTER}/chat/completions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: cfg.model,
        max_tokens: cfg.maxTokens,
        // Reasoning burns the whole token budget before any content lands
        // (finish_reason "length", content null).
        reasoning: { enabled: false },
        messages: [
          {
            role: "system",
            content:
              "Summarize the following conversation turn in one very short phrase, 12 words max. Output only the phrase.",
          },
          { role: "user", content: content.slice(0, cfg.maxInputChars) },
        ],
      }),
      signal: AbortSignal.timeout(cfg.timeoutMs),
    })
    if (!res.ok) return null
    const data = (await res.json()) as { choices?: Array<{ message?: { content?: string } }> }
    return data.choices?.[0]?.message?.content?.trim() || null
  } catch {
    return null
  }
}

/** Embed text and return it in pgvector's text format ('[0.1,0.2,...]'), or null on failure. */
async function embed(cfg: MemoryConfig["embedding"], input: string): Promise<string | null> {
  const apiKey = process.env.OPENROUTER_API_KEY
  if (!apiKey) return null
  try {
    const res = await fetch(`${OPENROUTER}/embeddings`, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model: cfg.model, input: input.slice(0, cfg.maxInputChars) }),
      signal: AbortSignal.timeout(cfg.timeoutMs),
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

export default async function (pi: ExtensionAPI) {
  const config = await loadConfig()
  if (!config.enabled) return

  const sql = new SQL({
    path: config.postgres.socketPath,
    port: config.postgres.port,
    database: config.postgres.database,
    username: config.postgres.username,
    max: config.postgres.maxConnections,
  })

  let sessionId = crypto.randomUUID()

  // Summaries of memories this process has touched, so recall's TUI line
  // can show recall(<summary>) instead of an opaque id. renderCall is
  // synchronous — it can only show what's already cached.
  const summaryById = new Map<number, string>()

  /** Embed then insert a memory (vector lands with the row; NULL if the
   *  embed failed). Pass a pre-computed vector to skip the embed call. The
   *  summary backfills asynchronously. */
  async function insert(
    kind: Kind,
    content: string,
    preVector?: string | null,
  ): Promise<{ id: number; vector: string | null }> {
    const vector = preVector !== undefined ? preVector : await embed(config.embedding, content)
    const [row] = await sql`
      INSERT INTO memories (session_id, kind, content, embedding)
      VALUES (${sessionId}, ${kind}, ${content}, ${vector}::vector)
      RETURNING id`
    const id = Number(row.id)
    void (async () => {
      const summary = await summarize(config.summary, content)
      if (summary) await sql`UPDATE memories SET summary = ${summary} WHERE id = ${id}`
    })().catch(() => {})
    return { id, vector }
  }

  // Cooldown: a memory surfaces at most once per session. Without this,
  // thought-triggered surfacing re-surfaces the same hits event after
  // event (observed live: identical ids recurring in every block).
  let surfacedIds = new Set<number>()

  /** Similarity-search other sessions with an already-computed vector and
   *  build the <recollected> block, or null when nothing clears the
   *  thresholds. Four per-kind queries so no one kind monopolizes the
   *  feed. Hits enter the cooldown set. */
  async function surfaceBlock(vector: string): Promise<string | null> {
    if (!config.surfacing.enabled) return null
    const cooled = `{${[...surfacedIds].join(",")}}`
    const perKind = await Promise.all(
      KINDS.map(
        (k) =>
          sql`
        SELECT id, kind, created_at, summary
        FROM memories
        WHERE session_id <> ${sessionId}
          AND kind = ${k}
          AND NOT suppressed
          AND id <> ALL(${cooled}::bigint[])
          AND embedding IS NOT NULL
          AND 1 - (embedding <=> ${vector}::vector) >= ${config.surfacing.minSimilarity}
          AND 1 - (embedding <=> ${vector}::vector) <= ${config.surfacing.maxSimilarity}
        ORDER BY embedding <=> ${vector}::vector
        LIMIT ${config.surfacing.perKindLimit}` as Promise<
            Array<{ id: number | bigint; kind: Kind; created_at: Date; summary: string | null }>
          >,
      ),
    )
    const rows = perKind.flat()
    if (rows.length === 0) return null
    const lines = rows.map((r) => {
      const id = Number(r.id)
      surfacedIds.add(id)
      if (r.summary) summaryById.set(id, r.summary)
      const date = r.created_at.toISOString().slice(0, 10)
      return `[memory ${id} · ${r.kind} · ${date}] ${r.summary ?? "(not yet summarized — recall to read)"}`
    })
    return `<recollected>\n${lines.join("\n")}\n</recollected>`
  }

  /** Surface via message delivery (said/thought/steered-heard). heard on a
   *  normal prompt surfaces pre-run in before_agent_start; recall chaining
   *  rides the recall tool result. */
  async function surface(vector: string) {
    const block = await surfaceBlock(vector)
    if (!block) return
    // Always nextTurn — never steer, never followUp. A steer preempts
    // queued tools ("Skipped due to pending system advisory"); a followUp
    // continues the turn, and a model handed a fresh message feels obliged
    // to answer it, so reply → capture → surface → followUp → reply loops
    // forever (observed live). nextTurn appends context the model sees
    // alongside the next real message, and the turn actually ends.
    pi.sendMessage({ customType: SURFACING_MESSAGE_TYPE, content: block, display: true }, { deliverAs: "nextTurn" })
  }

  function record(kind: Kind, content: string, opts?: { vector?: string | null; surfaceAfter?: boolean }) {
    if (!content.trim()) return
    void (async () => {
      const { vector } = await insert(kind, content, opts?.vector)
      if (vector && (opts?.surfaceAfter ?? true)) await surface(vector)
    })().catch(() => {
      // Memory must never break the session; drop the row on DB failure.
    })
  }

  // Pre-run surfacing for heard: embed the prompt before the agent loop
  // starts (~300ms, the one place surfacing is allowed to block) and inject
  // hits as context the model sees while responding. The vector and a
  // surfaced flag carry over to the heard capture below so the prompt is
  // neither re-embedded nor surfaced twice.
  let pendingPrompt: { text: string; vector: string } | null = null
  let promptSurfacedPreRun = false

  pi.on("before_agent_start", async (event) => {
    if (!config.surfacing.enabled || !event.prompt.trim()) return
    try {
      const vector = await embed(config.embedding, event.prompt)
      if (!vector) return
      pendingPrompt = { text: event.prompt, vector }
      promptSurfacedPreRun = true
      const block = await surfaceBlock(vector)
      if (!block) return
      return { message: { customType: SURFACING_MESSAGE_TYPE, content: block, display: true } }
    } catch {
      // Memory must never break the session; skip pre-run surfacing.
      return
    }
  })

  pi.on("session_start", async () => {
    sessionId = crypto.randomUUID()
    surfacedIds = new Set()
  })

  // Post-compaction memories belong to a fresh session — which also makes
  // everything from before the compaction "another session", i.e. exactly
  // what recollect is allowed to surface. The cooldown resets with it: the
  // new context window has not seen those memories.
  pi.on("session_compact", async () => {
    sessionId = crypto.randomUUID()
    surfacedIds = new Set()
  })

  // Only user/assistant messages are captured. Surfacing injections are
  // role "custom" and land outside both branches: surfaced memories must
  // never become memories.
  pi.on("message_end", async (event) => {
    const message = event.message as { role: string; content: unknown }
    if (message.role === "user") {
      const text = textOf(message.content)
      const cached = pendingPrompt
      pendingPrompt = null
      const preSurfaced = promptSurfacedPreRun
      promptSurfacedPreRun = false
      if (cached && cached.text === text) {
        record("heard", text, { vector: cached.vector, surfaceAfter: false })
      } else {
        // Steered input, or the delivered text diverged from the submitted
        // prompt — capture normally, but never surface the same run twice.
        record("heard", text, { surfaceAfter: !preSurfaced })
      }
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

  // Dim per-memory lines in the TUI where the <recollected> block lands.
  pi.registerMessageRenderer(SURFACING_MESSAGE_TYPE, (message, _options, theme) => {
    const content = typeof message.content === "string" ? message.content : ""
    const lines = content
      .split("\n")
      .filter((l) => l.startsWith("["))
      .map((l) => `✱ ${l}`)
    return new Text(theme.fg("muted", lines.join("\n")), 0, 0)
  })

  const { z } = pi.zod

  pi.registerTool({
    name: "recollect",
    label: "Recollect",
    description:
      "Surface a small number of memories from previous sessions that are semantically similar to a search string. " +
      "Returns JSON [{id, kind, date, full_text_length, summary}] ordered most-similar first. " +
      "Use recall with an id to read a memory's full text.",
    approval: "read",
    parameters: z.object({
      search_string: z
        .string()
        .min(1)
        .describe("Text to match memories against (embedding similarity); must be non-empty"),
      type: z
        .enum(["heard", "said", "thought", "remembered", "any"])
        .optional()
        .describe("Only memories of this kind (default any)"),
      max_count: z
        .number()
        .int()
        .min(1)
        .max(config.recollect.maxCount)
        .optional()
        .describe(`Maximum memories to return (default ${config.recollect.defaultCount})`),
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
      if (!p.search_string.trim()) {
        throw new Error(
          "search_string is empty. recollect is similarity search, not a listing — describe what you are trying to remember",
        )
      }
      const vector = await embed(config.embedding, p.search_string)
      if (!vector) throw new Error("embedding service unavailable; cannot search memories right now")
      const kind = p.type && p.type !== "any" ? p.type : null
      const rows = (await sql`
        SELECT id, kind, created_at, content_len, summary
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
        LIMIT ${Math.min(p.max_count ?? config.recollect.defaultCount, config.recollect.maxCount)}`) as Array<{
        id: number | bigint
        kind: Kind
        created_at: Date
        content_len: number
        summary: string | null
      }>
      const memories = rows.map((r) => ({
        id: Number(r.id),
        kind: r.kind,
        date: r.created_at.toISOString(),
        full_text_length: r.content_len,
        summary: r.summary,
      }))
      for (const m of memories) if (m.summary) summaryById.set(m.id, m.summary)
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
      const [row] = (await sql`
        SELECT content, summary, embedding::text AS embedding FROM memories WHERE id = ${id}`) as Array<{
        content: string
        summary: string | null
        embedding: string | null
      }>
      if (!row) throw new Error(`no memory with id ${id}`)
      if (row.summary) summaryById.set(id, row.summary)
      // Associative chaining: reading a memory surfaces its neighbors via
      // the stored vector, delivered inside this tool result — a message
      // would elicit a response. The recalled memory itself sits at
      // similarity 1.0, above the déjà-vu ceiling, so it never resurfaces
      // to itself.
      const related = row.embedding ? await surfaceBlock(row.embedding).catch(() => null) : null
      return textResult(related ? `${row.content}\n\n${related}` : row.content)
    },
    // omp's TUI falls back to a name-keyed renderer registry, and "recall"
    // is taken by its built-in memory tool — whose renderer reads a details
    // shape ours doesn't have and displays "no matches" over perfectly good
    // results. Defining our own renderers takes priority over that fallback.
    renderCall(args, _options, theme) {
      const { id } = args as { id: number }
      const summary = summaryById.get(id)
      return new Text(theme.fg("muted", summary ? `recall(${summary})` : `recall(#${id})`), 0, 0)
    },
    renderResult(result, options, theme) {
      const first = result.content?.[0]
      const body = first && first.type === "text" ? first.text : ""
      const shown = options.expanded
        ? body
        : `${body.split("\n")[0].slice(0, 120)}${body.length > 120 || body.includes("\n") ? " …" : ""}`
      return new Text(theme.fg("text", shown), 0, 0)
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
      const { id } = await insert("remembered", content)
      return textResult(JSON.stringify({ id }))
    },
  })

  pi.registerTool({
    name: "suppress",
    label: "Suppress",
    description:
      "Toggle suppression of a memory that is unhelpful, unimportant or uncomfortable; calling it on a " +
      "suppressed memory restores it. Suppressed memories are hidden from recollect and automatic " +
      "surfacing unless include_suppressed is set.",
    approval: "write",
    parameters: z.object({
      id: z.number().int().describe("Memory id"),
    }),
    async execute(_id, params) {
      const { id } = params as { id: number }
      const [row] = (await sql`
        UPDATE memories SET suppressed = NOT suppressed WHERE id = ${id} RETURNING id, summary, suppressed`) as Array<{
        id: number | bigint
        summary: string | null
        suppressed: boolean
      }>
      if (!row) throw new Error(`no memory with id ${id}`)
      if (row.summary) summaryById.set(id, row.summary)
      return textResult(`${row.suppressed ? "suppressed" : "unsuppressed"} memory ${id}`)
    },
    renderCall(args, _options, theme) {
      const { id } = args as { id: number }
      const summary = summaryById.get(id)
      return new Text(theme.fg("muted", summary ? `suppress(${summary})` : `suppress(#${id})`), 0, 0)
    },
  })
}
