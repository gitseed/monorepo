// OpenRouter API calls for the memory extension: summarization and
// embedding. Both read OPENROUTER_API_KEY from the env (a secret, not
// config) and return null on any failure — the caller treats null as
// "service unavailable", never as a fabricated stand-in.

import type { MemoryConfig } from "./config"

const OPENROUTER = "https://openrouter.ai/api/v1"

/** One-phrase summary from the summary model, or null on any failure. No
 *  fabricated stand-ins: a NULL summary column is the loud, queryable
 *  signal that summarization failed or hasn't run. */
export async function summarize(
  cfg: MemoryConfig["summary"],
  content: string,
): Promise<string | null> {
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
export async function embed(
  cfg: MemoryConfig["embedding"],
  input: string,
): Promise<string | null> {
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
