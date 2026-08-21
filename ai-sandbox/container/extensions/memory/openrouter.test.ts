// Contract tests for summarize()'s SSE handling: accumulation across
// frames, tolerance of keepalive comments and malformed frames, and — the
// failure mode that motivated streaming — null on a stream cut before the
// [DONE] sentinel rather than a silently truncated summary.
import { describe, expect, test } from "bun:test"
import { summarize } from "./openrouter"

process.env.OPENROUTER_API_KEY ??= "test-key"

const cfg = { model: "m", maxInputChars: 1000, maxTokens: 40, timeoutMs: 1000 }

type FetchMock = (input: string | URL | Request, init?: RequestInit) => Promise<Response>

async function sseResponse(frames: string[], status = 200): Promise<Response> {
  let i = 0
  return new Response(
    new ReadableStream({
      pull(controller) {
        if (i < frames.length) controller.enqueue(new TextEncoder().encode(frames[i++]))
        else controller.close()
      },
    }),
    { status },
  )
}

async function withFetch<T>(mock: FetchMock, run: () => Promise<T>): Promise<T> {
  const real = globalThis.fetch
  // Bun's fetch type carries a preconnect member the mocks omit.
  globalThis.fetch = mock as typeof fetch
  try {
    return await run()
  } finally {
    globalThis.fetch = real
  }
}

describe("summarize", () => {
  test("accumulates delta.content across frames; skips comments and malformed frames; stops at [DONE]", async () => {
    await withFetch(
      () =>
        sseResponse([
          ': OPENROUTER PROCESSING\n\n',
          'data: {"choices":[{"delta":{"content":"One"}}]}\n\n',
          'data: {broken json\n\n',
          'data: {"choices":[{"delta":{"content":" phrase"}}]}\n\n',
          "data: [DONE]\n\n",
          'data: {"choices":[{"delta":{"content":" IGNORED"}}]}\n\n',
        ]),
      async () => expect(await summarize(cfg, "hello")).toBe("One phrase"),
    )
  })

  test("clean early close before [DONE] yields null, not a truncated phrase", async () => {
    await withFetch(
      () => sseResponse(['data: {"choices":[{"delta":{"content":"One"}}]}\n\n']),
      async () => expect(await summarize(cfg, "hello")).toBeNull(),
    )
  })

  test("empty content with [DONE] yields null", async () => {
    await withFetch(
      () =>
        sseResponse([
          'data: {"choices":[{"delta":{"content":""}}]}\n\n',
          "data: [DONE]\n\n",
        ]),
      async () => expect(await summarize(cfg, "hello")).toBeNull(),
    )
  })

  test("non-2xx response yields null", async () => {
    await withFetch(
      () => sseResponse(["data: [DONE]\n\n"], 500),
      async () => expect(await summarize(cfg, "hello")).toBeNull(),
    )
  })
})
