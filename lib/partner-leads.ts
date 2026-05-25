// Server action used by the 4 partner-service forms (Espaços, Convidados,
// Música, Marketing). Inserts an anonymous lead into airfnb_partner_leads
// (anyone can insert per the RLS policy) and fires an email via the
// existing send-email edge function.
//
// Email destinations are currently env-var placeholders. TODO: move to
// /admin/definicoes once that settings page exists.
"use server";

import { supabaseServer } from "@/lib/supabase/server";
import { getSetting } from "@/lib/settings";

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

  const name  = String(formData.get("name")  ?? "").trim();
  const email = String(formData.get("email") ?? "").trim();
  const phone = String(formData.get("phone") ?? "").trim() || null;

  if (!name)  return { ok: false, error: "Indica o teu nome." };
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return { ok: false, error: "Email inválido." };
  }

  // Everything else goes into payload as-is — the form per kind defines
  // its own fields. We strip empty strings to keep the jsonb compact.
  const payload: Record<string, string | string[]> = {};
  for (const [k, v] of formData.entries()) {
    if (k === "name" || k === "email" || k === "phone" || k === "website") continue;
    const s = String(v).trim();
    if (!s) continue;
    // Multi-select form fields show up multiple times — collect into array.
    if (k in payload) {
      const cur = payload[k];
      payload[k] = Array.isArray(cur) ? [...cur, s] : [cur, s];
    } else {
      payload[k] = s;
    }
  }

  const supa = await supabaseServer();
  const { error } = await (supa as any)
    .from("airfnb_partner_leads")
    .insert({ kind, name, email, phone, payload });

  if (error) {
    return { ok: false, error: `Não conseguimos guardar o pedido: ${error.message}` };
  }

  // Fire-and-forget email notification. Look up the destination from
  // /admin/definicoes first; if blank, fall back to the env var so a
  // first-time deploy works before the team has touched the settings page.
  const to = await getSetting(
    SETTING_KEY_BY_KIND[kind],
    process.env[ENV_FALLBACK_BY_KIND[kind]],
  );
  if (to) {
    try {
      const url = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/send-email`;
      await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY ?? ""}`,
        },
        body: JSON.stringify({
          to,
          template: "contact_reply", // generic template; payload rendered as HTML in the edge fn
          subject: SUBJECT_BY_KIND[kind],
          data: { name, email, phone, kind, ...payload },
        }),
      });
    } catch (e) {
      // Log but don't fail the user flow — the lead is in the DB.
      console.warn("partner-lead email dispatch failed", e);
    }
  }

  return { ok: true };
}
