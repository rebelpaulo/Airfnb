import { resolveAppOrigin } from "@/lib/app-url.mjs";

export const PUBLIC_CONTACT_FALLBACK_PATH = "/ajuda";

export type PublicContactKind =
  | "support"
  | "partnerships"
  | "privacy"
  | "legal";

const RESERVED_DOMAINS = new Set([
  "example",
  "example.com",
  "example.net",
  "example.org",
  "invalid",
  "local",
  "localhost",
  "test",
]);

/**
 * Accept only a plain mailbox address suitable for a public mailto link.
 * Display-name forms belong in FROM_EMAIL and are deliberately rejected here.
 */
export function validatePublicEmail(value: string | undefined): string | null {
  const email = value?.trim();
  if (!email || email.length > 254 || /[\r\n<>]/.test(email)) return null;
  if (
    !/^[A-Za-z0-9][A-Za-z0-9.!%&'*+/=_~-]*@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$/.test(email)
  ) {
    return null;
  }

  const domain = email.slice(email.lastIndexOf("@") + 1).toLowerCase();
  if (
    RESERVED_DOMAINS.has(domain) ||
    domain.endsWith(".example") ||
    domain.endsWith(".invalid") ||
    domain.endsWith(".local") ||
    domain.endsWith(".localhost") ||
    domain.endsWith(".test")
  ) {
    return null;
  }

  return email;
}

function configuredContacts(): Record<PublicContactKind, string | null> {
  const support = validatePublicEmail(process.env.SUPPORT_EMAIL);

  return {
    support,
    partnerships: validatePublicEmail(process.env.PARTNERSHIP_EMAIL) ?? support,
    privacy: validatePublicEmail(process.env.PRIVACY_EMAIL) ?? support,
    legal: validatePublicEmail(process.env.LEGAL_EMAIL) ?? support,
  };
}

export function getPublicContactEmail(kind: PublicContactKind): string | null {
  return configuredContacts()[kind];
}

export function getPublicContactHref(kind: PublicContactKind): string {
  const email = getPublicContactEmail(kind);
  return email ? `mailto:${email}` : PUBLIC_CONTACT_FALLBACK_PATH;
}

export function getCanonicalHost(): string {
  return new URL(resolveAppOrigin()).host;
}
