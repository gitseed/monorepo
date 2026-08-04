// OpenRouter model discovery — restores omp's dynamic model metadata.
//
// pi's auto-refreshing catalog only covers built-in providers; a custom
// openrouter provider in models.json knows only what's written there
// (contextWindow defaults to 128k). omp instead fetched OpenRouter's public
// /api/v1/models at startup and mapped context_length, max_completion_tokens,
// pricing, and modalities per model. This extension does the same for the
// models listed in models.json, then re-registers the provider in-memory via
// pi.registerProvider. models.json stays the offline fallback: on any fetch
// or parse failure this is a silent no-op.

import { readFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"
import type { ExtensionAPI, ProviderConfig, ProviderModelConfig } from "@earendil-works/pi-coding-agent"

const MODELS_URL = "https://openrouter.ai/api/v1/models"
const FETCH_TIMEOUT_MS = 8_000

// pi's own defaults for unspecified models.json fields.
const DEFAULTS = {
  reasoning: false,
  input: ["text"] as ("text" | "image")[],
  contextWindow: 128_000,
  maxTokens: 16_384,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
}

interface CatalogEntry {
  id: string
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

/** models.json entry (sparse) -> full ProviderModelConfig, with live catalog metadata overlaid (discovery wins, as in omp). */
function resolve(model: { id: string } & Partial<ProviderModelConfig>, entry: CatalogEntry | undefined): ProviderModelConfig {
  const base: ProviderModelConfig = {
    name: model.id,
    ...DEFAULTS,
    ...model,
    id: model.id,
  }
  if (!entry) return base
  const params = Array.isArray(entry.supported_parameters) ? entry.supported_parameters : []
  const modality = String(entry.architecture?.modality ?? "")
  const maxCompletion = entry.top_provider?.max_completion_tokens
  return {
    ...base,
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
  const agentDir = process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent")

  let provider: (ProviderConfig & { models?: Array<{ id: string } & Partial<ProviderModelConfig>> }) | undefined
  try {
    provider = JSON.parse(readFileSync(join(agentDir, "models.json"), "utf-8")).providers?.openrouter
  } catch {
    return
  }
  const staticModels = provider?.models
  if (!provider || !Array.isArray(staticModels) || staticModels.length === 0) return

  let catalog: Map<string, CatalogEntry>
  try {
    const res = await fetch(MODELS_URL, { signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) })
    if (!res.ok) return
    const data = (await res.json()) as { data?: CatalogEntry[] }
    if (!Array.isArray(data.data)) return
    catalog = new Map(data.data.map((e) => [e.id, e]))
  } catch {
    return
  }
  if (!staticModels.some((m) => catalog.has(m.id))) return

  // Queued during the factory; applied to the model runtime before the
  // session starts. In-memory only — models.json is never rewritten.
  pi.registerProvider("openrouter", {
    baseUrl: provider.baseUrl,
    apiKey: provider.apiKey,
    api: provider.api,
    models: staticModels.map((m) => resolve(m, catalog.get(m.id))),
  })
}
