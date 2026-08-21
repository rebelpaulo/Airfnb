const PUBLIC_AVATAR_PREFIX = "/storage/v1/object/public/airfnb-avatars/";
const UUID_SEGMENT = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const OBJECT_SEGMENT = /^[a-z0-9][a-z0-9._-]*$/i;
const MAX_PUBLIC_AVATAR_URL_LENGTH = 2048;

/**
 * Return only first-party public avatar object URLs accepted by next/image.
 * Stored profile text is not trusted merely because it came from Supabase.
 */
export function publicAvatarUrl(
  value: unknown,
  configuredSupabaseUrl: string | undefined,
): string | null {
  if (
    typeof value !== "string"
    || !value.trim()
    || value.length > MAX_PUBLIC_AVATAR_URL_LENGTH
    || !configuredSupabaseUrl?.trim()
  ) {
    return null;
  }

  try {
    const configured = new URL(configuredSupabaseUrl.trim());
    const candidate = new URL(value.trim());
    if (
      !["http:", "https:"].includes(configured.protocol)
      || configured.username
      || configured.password
      || configured.pathname !== "/"
      || configured.search
      || configured.hash
      || candidate.origin !== configured.origin
      || candidate.username
      || candidate.password
      || candidate.search
      || candidate.hash
      || !candidate.pathname.startsWith(PUBLIC_AVATAR_PREFIX)
    ) {
      return null;
    }

    const objectPath = candidate.pathname.slice(PUBLIC_AVATAR_PREFIX.length);
    const [ownerId, ...objectSegments] = objectPath.split("/");
    if (
      !UUID_SEGMENT.test(ownerId)
      || objectSegments.length === 0
      || objectSegments.some((segment) => !OBJECT_SEGMENT.test(segment))
    ) {
      return null;
    }

    return candidate.href;
  } catch {
    return null;
  }
}
