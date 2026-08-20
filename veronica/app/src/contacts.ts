// The caller allowlist lives in the contacts KV namespace (owned by
// ../tofu): one key per allowed caller's name, the phone number typed into
// the Cloudflare dashboard by hand so it never enters the repo. Presence
// of an E.164 number authorizes the caller; empty or malformed values are
// just skipped.

const E164 = /^\+[1-9][0-9]{1,14}$/;

export async function allowedNumbers(env: Env): Promise<Set<string>> {
  const { keys } = await env.CONTACTS.list();
  const values = await Promise.all(keys.map((k) => env.CONTACTS.get(k.name)));
  return new Set(values.map((v) => (v ?? "").replace(/\s+/g, "")).filter((v) => E164.test(v)));
}
