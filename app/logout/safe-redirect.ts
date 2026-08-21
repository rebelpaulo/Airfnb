const ENCODED_PATH_SEPARATOR = /%(?:2f|5c)/i;

export function safeRedirectUrl(raw: string | null, origin: string): URL {
  const fallback = new URL("/", origin);
  const rawPath = raw?.split(/[?#]/, 1)[0] ?? "";

  if (
    !raw ||
    !raw.startsWith("/") ||
    raw.startsWith("//") ||
    rawPath.includes("\\") ||
    ENCODED_PATH_SEPARATOR.test(rawPath)
  ) {
    return fallback;
  }

  try {
    const target = new URL(raw, origin);
    if (
      target.origin !== fallback.origin ||
      target.pathname.startsWith("//") ||
      target.pathname.includes("\\") ||
      ENCODED_PATH_SEPARATOR.test(target.pathname)
    ) {
      return fallback;
    }
    return target;
  } catch {
    return fallback;
  }
}
