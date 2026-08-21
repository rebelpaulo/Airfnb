const LOCAL_ORIGIN = "http://localhost:3001";

/**
 * Normalize a configured deployment URL to an HTTP(S) origin.
 * Vercel exposes hostnames without a scheme, so those two candidates are
 * explicitly promoted to HTTPS. User-configured URLs must include a scheme.
 *
 * @param {unknown} value
 * @param {{ vercelHostname?: boolean }} [options]
 * @returns {string | null}
 */
export function normalizeAppOrigin(value, options = {}) {
  if (typeof value !== "string" || !value.trim()) return null;

  const candidate = value.trim();
  const withScheme = options.vercelHostname && !candidate.includes("://")
    ? `https://${candidate}`
    : candidate;

  try {
    const url = new URL(withScheme);
    if (url.protocol !== "http:" && url.protocol !== "https:") return null;
    if (url.username || url.password) return null;
    return url.origin;
  } catch {
    return null;
  }
}

/**
 * Resolve the canonical runtime origin without assuming a production domain.
 * Invalid values fall through to the next source in the documented order.
 *
 * @param {Record<string, string | undefined>} [env]
 * @returns {string}
 */
export function resolveAppOrigin(env = process.env) {
  const candidates = [
    [env.APP_URL, false],
    [env.NEXT_PUBLIC_APP_URL, false],
    [env.VERCEL_PROJECT_PRODUCTION_URL, true],
    [env.VERCEL_URL, true],
  ];

  for (const [value, vercelHostname] of candidates) {
    const origin = normalizeAppOrigin(value, { vercelHostname });
    if (origin) return origin;
  }

  return LOCAL_ORIGIN;
}
