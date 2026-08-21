// Server action used by the 4 partner-service forms (Espaços, Convidados,
// Música, Marketing). Inserts an anonymous lead into airfnb_partner_leads
// through the trusted service-role client and fires an email via the
// existing send-email edge function.
//
// Email destinations are currently env-var placeholders. TODO: move to
// /admin/definicoes once that settings page exists.
"use server";

import { headers } from "next/headers";
import { supabaseAdmin } from "@/lib/supabase/server";
import { getSetting } from "@/lib/settings";
import {
  assertPublicRateLimit,
  PublicRateLimitError,
  publicClientIp,
} from "@/lib/public-rate-limit";

export type LeadKind = "venues" | "guest_mgmt" | "music" | "marketing";

// First place we look is `airfnb_platform_settings` (edited via
// /admin/definicoes). Env vars are now the *fallback* — kept so a fresh
// install without DB rows still works, and so the team can override per
// preview environment without touching the DB.
const SETTING_KEY_BY_KIND: Record<LeadKind, string> = {
  venues:     "partner_email_venues",
  guest_mgmt: "partner_email_guest_mgmt",
  music:      "partner_email_music",
  marketing:  "partner_email_marketing",
};
const ENV_FALLBACK_BY_KIND: Record<LeadKind, string> = {
  venues:     "PARTNER_EMAIL_VENUES",
  guest_mgmt: "PARTNER_EMAIL_GUEST_MGMT",
  music:      "PARTNER_EMAIL_MUSIC",
  marketing:  "PARTNER_EMAIL_MARKETING",
};

const SUBJECT_BY_KIND: Record<LeadKind, string> = {
  venues:     "Novo pedido: espaço para evento",
  guest_mgmt: "Novo pedido: gestão de convidados / 3cket",
  music:      "Novo pedido: música & animação",
  marketing:  "Novo pedido: marketing & publicidade",
};

const LEAD_KIND_LABEL: Record<LeadKind, string> = {
  venues: "Espaços para eventos",
  guest_mgmt: "Gestão de convidados",
  music: "Música e animação",
  marketing: "Marketing e publicidade",
};

const EMAIL_CONTROL_FIELDS = new Set([
  "from",
  "html",
  "kind",
  "message",
  "reply_to",
  "replyTo",
  "subject",
  "template",
  "to",
  "website",
]);
const MAX_LEAD_EMAIL_MESSAGE_LENGTH = 9_000;

function compactEmailValue(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

function partnerLeadEmailMessage(
  kind: LeadKind,
  name: string,
  email: string,
  phone: string | null,
  payload: Record<string, string | string[]>,
): string {
  const fields = [
    `Serviço: ${LEAD_KIND_LABEL[kind]}`,
    `Nome: ${compactEmailValue(name)}`,
    `Email: ${compactEmailValue(email)}`,
  ];

  if (phone) fields.push(`Telefone: ${compactEmailValue(phone)}`);

  for (const key of Object.keys(payload).sort()) {
    if (EMAIL_CONTROL_FIELDS.has(key)) continue;
    const rawValue = payload[key];
    const value = Array.isArray(rawValue)
      ? rawValue.map(compactEmailValue).filter(Boolean).join(", ")
      : compactEmailValue(rawValue);
    if (!value) continue;
    fields.push(`${key.replaceAll("_", " ")}: ${value}`);
  }

  // All values remain plain text. The contact_reply template owns HTML
  // escaping, so form content can never become markup here.
  return fields.join(" · ").slice(0, MAX_LEAD_EMAIL_MESSAGE_LENGTH);
}

export type LeadResult =
  | { ok: true }
  | { ok: false; error: string };

export async function submitPartnerLead(
  kind: LeadKind,
  formData: FormData,
): Promise<LeadResult> {
  // Honeypot: bots tend to fill every input including hidden ones. If the
  // `website` field has a value, silently succeed (don't tell the bot).
  if (String(formData.get("website") ?? "").trim() !== "") {
    return { ok: true };
  }

  if (!Object.prototype.hasOwnProperty.call(SUBJECT_BY_KIND, kind)) {
    return { ok: false, error: "Pedido inválido." };
  }

  const nameValue = formData.get("name");
  const emailValue = formData.get("email");
  const phoneValue = formData.get("phone");
  if (
    typeof nameValue !== "string"
    || typeof emailValue !== "string"
    || (phoneValue !== null && typeof phoneValue !== "string")
  ) {
    return { ok: false, error: "Pedido inválido." };
  }

  const name = nameValue.trim();
  const email = emailValue.trim().toLowerCase();
  const phone = phoneValue?.trim() || null;

  if (!name)  return { ok: false, error: "Indica o teu nome." };
  if (name.length > 120 || (phone?.length ?? 0) > 40) {
    return { ok: false, error: "Pedido demasiado longo." };
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) {
    return { ok: false, error: "Email inválido." };
  }

  // Everything else goes into payload as-is — the form per kind defines
  // its own fields. We strip empty strings to keep the jsonb compact.
  const payload: Record<string, string | string[]> = {};
  let payloadFields = 0;
  let payloadCharacters = 0;
  for (const [k, v] of formData.entries()) {
    if (k === "name" || k === "email" || k === "phone" || k === "website") continue;
    if (
      typeof v !== "string"
      || !/^[a-z][a-z0-9_]{0,63}$/.test(k)
      || v.length > 2_000
    ) {
      return { ok: false, error: "Pedido inválido." };
    }
    const s = v.trim();
    if (!s) continue;
    payloadFields += 1;
    payloadCharacters += k.length + s.length;
    if (payloadFields > 32 || payloadCharacters > 8_000) {
      return { ok: false, error: "Pedido demasiado longo." };
    }
    // Multi-select form fields show up multiple times — collect into array.
    if (k in payload) {
      const cur = payload[k];
      payload[k] = Array.isArray(cur) ? [...cur, s] : [cur, s];
    } else {
      payload[k] = s;
    }
  }

  try {
    await assertPublicRateLimit({
      action: `partner_lead_${kind}_email`,
      identifierKind: "email",
      identifier: email,
      limit: 5,
      windowSeconds: 86_400,
    });

    const ip = publicClientIp(await headers());
    if (ip) {
      await assertPublicRateLimit({
        action: `partner_lead_${kind}_ip`,
        identifierKind: "ip",
        identifier: ip,
        limit: 20,
        windowSeconds: 3_600,
      });
    }
  } catch (error) {
    if (error instanceof PublicRateLimitError && error.code === "rate_limited") {
      return { ok: false, error: "Demasiados pedidos. Tenta novamente mais tarde." };
    }
    return { ok: false, error: "Não conseguimos validar o pedido. Tenta novamente." };
  }

  let insertError: { code?: string } | null = null;
  try {
    const result = await supabaseAdmin()
      .from("airfnb_partner_leads")
      .insert({ kind, name, email, phone, payload });
    insertError = result.error;
  } catch {
    insertError = { code: "client_unavailable" };
  }

  if (insertError) {
    return { ok: false, error: "Não conseguimos guardar o pedido. Tenta novamente." };
  }

  // Best-effort email notification. Look up the destination from
  // /admin/definicoes first; if blank, fall back to the env var so a
  // first-time deploy works before the team has touched the settings page.
  try {
    const to = await getSetting(
      SETTING_KEY_BY_KIND[kind],
      process.env[ENV_FALLBACK_BY_KIND[kind]],
    );
    if (to) {
      const url = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/send-email`;
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY ?? ""}`,
        },
        body: JSON.stringify({
          to,
          template: "contact_reply", // generic template; payload rendered as HTML in the edge fn
          subject: SUBJECT_BY_KIND[kind],
          replyTo: email,
          data: {
            name,
            email,
            phone,
            kind,
            message: partnerLeadEmailMessage(kind, name, email, phone, payload),
          },
        }),
      });
      if (!response.ok) throw new Error("email dispatch rejected");
    }
  } catch {
    // Generic and non-blocking: the persisted lead remains the source of truth.
    console.warn("partner-lead email dispatch failed");
  }

  return { ok: true };
}
