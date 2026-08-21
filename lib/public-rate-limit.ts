import "server-only";

import { createHmac } from "node:crypto";
import { isIP } from "node:net";
import { supabaseAdmin } from "@/lib/supabase/server";

const MAX_IDENTIFIER_LENGTH = 512;
const ACTION_PATTERN = /^[a-z][a-z0-9_]{0,63}$/;

type HeaderReader = Pick<Headers, "get">;

type RateLimitInput = {
  action: string;
  identifierKind: "email" | "ip";
  identifier: string;
  limit: number;
  windowSeconds: number;
};

export class PublicRateLimitError extends Error {
  readonly code: "rate_limited" | "unavailable";

  constructor(code: "rate_limited" | "unavailable") {
    super(code);
    this.name = "PublicRateLimitError";
    this.code = code;
  }
}

function rateLimitSecret(): string {
  const secret = process.env.PUBLIC_RATE_LIMIT_SECRET
    ?? process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!secret || secret.length < 32) {
    throw new PublicRateLimitError("unavailable");
  }

  return secret;
}

/**
 * Returns an opaque, stable bucket. Raw IP/email values never leave the
 * trusted server process and are never included in thrown errors.
 */
export function hashPublicRateLimitIdentifier(
  kind: "email" | "ip",
  identifier: string,
): string {
  const normalized = identifier.trim().toLowerCase();
  if (!normalized || normalized.length > MAX_IDENTIFIER_LENGTH) {
    throw new PublicRateLimitError("unavailable");
  }

  const digest = createHmac("sha256", rateLimitSecret())
    .update(`fb-tailor-public-rate-limit\0${kind}\0${normalized}`, "utf8")
    .digest("hex");

  return `v1:${kind}:${digest}`;
}

/** Extracts the first proxy-provided address without ever logging it. */
export function publicClientIp(headers: HeaderReader): string | null {
  const forwarded = headers.get("x-forwarded-for")
    ?.split(",")
    .map((value) => value.trim())
    .find(Boolean);
  const candidate = forwarded ?? headers.get("x-real-ip")?.trim();

  if (!candidate || candidate.length > 128 || /[\r\n]/.test(candidate) || isIP(candidate) === 0) {
    return null;
  }

  return candidate;
}

/**
 * Increments one trusted counter. Database errors fail closed; callers must
 * not continue to ingestion when this function throws.
 */
export async function assertPublicRateLimit(input: RateLimitInput): Promise<void> {
  if (
    !ACTION_PATTERN.test(input.action)
    || !Number.isInteger(input.limit)
    || input.limit < 1
    || input.limit > 10000
    || !Number.isInteger(input.windowSeconds)
    || input.windowSeconds < 1
    || input.windowSeconds > 2_678_400
  ) {
    throw new PublicRateLimitError("unavailable");
  }

  const bucket = hashPublicRateLimitIdentifier(
    input.identifierKind,
    input.identifier,
  );

  try {
    const { data, error } = await supabaseAdmin().rpc(
      "airfnb_check_rate_limit",
      {
        p_action: input.action,
        p_bucket: bucket,
        p_limit_per_window: input.limit,
        p_window_seconds: input.windowSeconds,
      },
    );

    if (error || data !== true) {
      throw new PublicRateLimitError(error ? "unavailable" : "rate_limited");
    }
  } catch (error) {
    if (error instanceof PublicRateLimitError) throw error;
    throw new PublicRateLimitError("unavailable");
  }
}
