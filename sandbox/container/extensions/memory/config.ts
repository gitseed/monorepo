// Memory extension configuration.
//
// Configured by /root/.omp/agent/memory.json (override the path with
// MEMORY_CONFIG); missing file or keys fall back to DEFAULTS below, with
// enabled=false, so the extension is inert until the config turns it on.
// OPENROUTER_API_KEY stays an env var — it's a secret, not config.

export const CONFIG_PATH = process.env.MEMORY_CONFIG || "/root/.omp/agent/memory.json"

export interface MemoryConfig {
  enabled: boolean
  postgres: {
    socketPath: string
    port: number
    database: string
    username: string
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

export const DEFAULTS: MemoryConfig = {
  enabled: false,
  postgres: {
    socketPath: "/var/run/postgresql",
    port: 5432,
    database: "memory",
    username: "omp",
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
    // Scale is model-specific: with text-embedding-3-small, echoes sit at
    // ~1.0, strong associations at ~0.45-0.55, noise below ~0.3 (measured
    // against a live corpus). A 0.55 floor left no band under the ceiling.
    minSimilarity: 0.4,
    maxSimilarity: 0.95,
    perKindLimit: 2,
  },
}

export type Kind = "heard" | "said" | "thought" | "remembered"
export const KINDS: Kind[] = ["heard", "said", "thought", "remembered"]

/** Load the config file, merging any present keys over the defaults. Returns
 *  DEFAULTS (extension disabled) on any read/parse failure. */
export async function loadConfig(): Promise<MemoryConfig> {
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
