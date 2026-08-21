export function normalizeAppOrigin(
  value: unknown,
  options?: { vercelHostname?: boolean },
): string | null;

export function resolveAppOrigin(
  env?: Record<string, string | undefined>,
): string;
