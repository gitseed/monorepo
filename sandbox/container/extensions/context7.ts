// Context7 — up-to-date library documentation for the agent.
//
// Two tools: resolve-library-id (search by name) and query-docs (fetch docs
// by library ID). Both call the Context7 REST API at context7.com/api.
// The API key is injected by the Envoy credentials proxy — the extension
// sends no Authorization header; the proxy adds it.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { z } from "zod";

const BASE_URL = "https://context7.com/api";

async function parseErrorResponse(response: Response): Promise<string> {
  try {
    const json = (await response.json()) as { message?: string };
    if (json.message) return json.message;
  } catch {
    // JSON parsing failed, fall through to status-based message
  }
  const hasKey = Boolean(process.env.CONTEXT7_API_KEY);
  if (response.status === 429) {
    return hasKey
      ? "Rate limited or quota exceeded. Upgrade your plan at https://context7.com/plans for higher limits."
      : "Rate limited or quota exceeded. Create a free API key at https://context7.com/dashboard for higher limits.";
  }
  if (response.status === 404) {
    return "The library you are trying to access does not exist. Please try with a different library ID.";
  }
  if (response.status === 401) {
    return "Invalid API key. API keys should start with 'ctx7sk' prefix.";
  }
  return `Request failed with status ${response.status}. Please try again later.`;
}

function sourceReputationLabel(score?: number): "High" | "Medium" | "Low" | "Unknown" {
  if (score === undefined || score < 0) return "Unknown";
  if (score >= 7) return "High";
  if (score >= 4) return "Medium";
  return "Low";
}

const textResult = (t: string) => ({ content: [{ type: "text" as const, text: t }] });

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "resolve-library-id",
    label: "Resolve Library ID",
    description:
      "Search the Context7 index by library name and return matching libraries with their Context7-compatible IDs. " +
      "Call this first, then use query-docs with the chosen library ID to fetch documentation.",
    approval: "read",
    parameters: z.object({
      query: z.string().describe("The user's question or task (used to rank results by relevance)"),
      libraryName: z.string().describe("The name of the library to search for"),
    }),
    async execute(_id, params) {
      const { query, libraryName } = params as { query: string; libraryName: string };
      const url = new URL(`${BASE_URL}/v2/libs/search`);
      url.searchParams.set("query", query);
      url.searchParams.set("libraryName", libraryName);

      const response = await fetch(url);
      if (!response.ok) {
        return textResult(await parseErrorResponse(response));
      }
      const data = (await response.json()) as {
        results?: Array<{
          id: string;
          title: string;
          description: string;
          totalSnippets?: number;
          trustScore?: number;
          benchmarkScore?: number;
          versions?: string[];
          source?: string;
        }>;
      };

      if (!data.results || data.results.length === 0) {
        return textResult("No libraries found matching the provided name.");
      }

      const formatted = data.results
        .map((r) => {
          const lines = [
            `- Title: ${r.title}`,
            `- Context7-compatible library ID: ${r.id}`,
            `- Description: ${r.description}`,
          ];
          if (r.totalSnippets !== undefined && r.totalSnippets !== -1) {
            lines.push(`- Code Snippets: ${r.totalSnippets}`);
          }
          lines.push(`- Source Reputation: ${sourceReputationLabel(r.trustScore)}`);
          if (r.benchmarkScore !== undefined && r.benchmarkScore > 0) {
            lines.push(`- Benchmark Score: ${r.benchmarkScore}`);
          }
          if (r.versions && r.versions.length > 0) {
            lines.push(`- Versions: ${r.versions.join(", ")}`);
          }
          if (r.source) {
            lines.push(`- Source: ${r.source}`);
          }
          return lines.join("\n");
        })
        .join("\n----------\n");

      return textResult(`Available Libraries:\n\n${formatted}`);
    },
  });

  pi.registerTool({
    name: "query-docs",
    label: "Query Docs",
    description:
      "Fetch up-to-date documentation and code examples for a library using its Context7-compatible library ID. " +
      "Use resolve-library-id first to get the ID, then call this with a specific question.",
    approval: "read",
    parameters: z.object({
      libraryId: z.string().describe("Exact Context7-compatible library ID (e.g. /vercel/next.js)"),
      query: z.string().describe("The question or task to get relevant documentation for"),
    }),
    async execute(_id, params) {
      const { libraryId, query } = params as { libraryId: string; query: string };
      const url = new URL(`${BASE_URL}/v2/context`);
      url.searchParams.set("query", query);
      url.searchParams.set("libraryId", libraryId);

      const response = await fetch(url);
      if (!response.ok) {
        return textResult(await parseErrorResponse(response));
      }

      const text = await response.text();
      if (!text) {
        return textResult(
          "Documentation not found for this library ID. Use resolve-library-id to find a valid Context7-compatible library ID.",
        );
      }
      return textResult(text);
    },
  });
}
