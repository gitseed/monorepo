// OpenRouter provider for pi — the provider is defined here, not in
// models.json (there is none). At startup this fetches OpenRouter's public
// /api/v1/models and registers every tool-capable model with live metadata
// (context_length, max_completion_tokens, pricing, reasoning, modalities),
// the way omp's bundled catalog worked — so /models shows the full list.
// If the fetch fails, a minimal fallback set is registered so the
// settings.json defaultModel (GLM 5.2) still resolves offline.

import type { ExtensionAPI, ProviderConfig, ProviderModelConfig } from "@earendil-works/pi-coding-agent"

const MODELS_URL = "https://openrouter.ai/api/v1/models"
const FETCH_TIMEOUT_MS = 8_000

const PROVIDER: ProviderConfig = {
  name: "OpenRouter",
  baseUrl: "https://openrouter.ai/api/v1",
  apiKey: "$OPENROUTER_API_KEY",
  api: "openai-completions",
}

const DEFAULTS = {
  reasoning: false,
  input: ["text"] as ("text" | "image")[],
  contextWindow: 128_000,
  maxTokens: 16_384,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
}

// Registered when the catalog is unreachable; defaultModel must exist.
const FALLBACK_MODELS: ProviderModelConfig[] = [
  { id: "z-ai/glm-5.2", name: "GLM 5.2", ...DEFAULTS, reasoning: true, contextWindow: 1_048_576, maxTokens: 262_144 },
  { id: "deepseek/deepseek-v4-flash-0731", name: "DeepSeek V4 Flash", ...DEFAULTS },
]

interface CatalogEntry {
  id: string
  name?: string
  context_length?: number
  pricing?: Record<string, unknown>
  top_provider?: { max_completion_tokens?: number | null }
  architecture?: { modality?: string }
  supported_parameters?: string[]
}

function perMillion(raw: unknown): number {
  const perToken = parseFloat(String(raw ?? "0"))
  return Number.isFinite(perToken) ? perToken * 1_000_000 : 0
}

/** Catalog entry -> full ProviderModelConfig (omp's mapping). */
function toModel(entry: CatalogEntry): ProviderModelConfig {
  const params = Array.isArray(entry.supported_parameters) ? entry.supported_parameters : []
  const modality = String(entry.architecture?.modality ?? "")
  const maxCompletion = entry.top_provider?.max_completion_tokens
  return {
    id: entry.id,
    name: entry.name || entry.id,
    ...DEFAULTS,
    reasoning: params.includes("reasoning"),
    input: modality.includes("image") ? ["text", "image"] : ["text"],
    ...(typeof entry.context_length === "number" ? { contextWindow: entry.context_length } : {}),
    ...(typeof maxCompletion === "number" ? { maxTokens: maxCompletion } : {}),
    cost: {
      input: perMillion(entry.pricing?.prompt),
      output: perMillion(entry.pricing?.completion),
      cacheRead: perMillion(entry.pricing?.input_cache_read),
      cacheWrite: perMillion(entry.pricing?.input_cache_write),
    },
  }
}

export default async function (pi: ExtensionAPI) {
  let models = FALLBACK_MODELS
  try {
    const res = await fetch(MODELS_URL, { signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) })
    if (res.ok) {
      const data = (await res.json()) as { data?: CatalogEntry[] }
      const catalog = (data.data ?? [])
        .filter((e) => Array.isArray(e.supported_parameters) && e.supported_parameters.includes("tools"))
        .map(toModel)
        .sort((a, b) => a.id.localeCompare(b.id))
      if (catalog.length > 0) models = catalog
    }
  } catch {
    // Offline or proxy hiccup: fall back to the static set.
  }

  // Queued during the factory; applied to the model runtime before the
  // session starts.
  pi.registerProvider("openrouter", { ...PROVIDER, models })
}
