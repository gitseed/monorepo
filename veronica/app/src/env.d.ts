// The two secrets are uploaded with `wrangler secret put` (SETUP.md), so
// `wrangler types` cannot see them; declare them onto the generated Env
// here. Everything else in Env comes from worker-configuration.d.ts.
interface Env {
  OPENAI_API_KEY: string;
  OPENAI_WEBHOOK_SECRET: string;
}

declare namespace Cloudflare {
  interface Env {
    OPENAI_API_KEY: string;
    OPENAI_WEBHOOK_SECRET: string;
  }
}
