// supabase/functions/send-email/index.ts
//
// Transactional email sender via Resend.
// Invoked from:
//   - SQL triggers (pg_net) on booking.status changes
//   - Postgres functions
//   - Frontend (e.g. contact form)
//
// Required env (set with `supabase secrets set`):
//   RESEND_API_KEY        — Resend API key
//   FROM_EMAIL            — default sender, e.g. "Air F&B <ola@airfnb.example>"
//   ALLOWED_TEMPLATES     — comma-separated whitelist, e.g. "booking_confirmed,proposal_sent,contact_reply"
//
// Invoke:
//   POST /functions/v1/send-email
//   { "to": "x@y.com", "template": "booking_confirmed", "data": { ... }, "subject": "..." }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, handlePreflight, json } from "../_shared/cors.ts";

type Payload = {
  to: string | string[];
  template: TemplateKey;
  data: Record<string, unknown>;
  subject?: string;
  replyTo?: string;
};

type TemplateKey =
  | "booking_inquiry_received"
  | "proposal_sent"
  | "booking_confirmed"
  | "booking_cancelled"
  | "payment_received"
  | "review_request"
  | "contact_reply"
  | "newsletter_confirm";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const FROM_EMAIL     = Deno.env.get("FROM_EMAIL")   ?? "Air F&B <noreply@airfnb.local>";
const ALLOWED        = (Deno.env.get("ALLOWED_TEMPLATES") ?? "")
  .split(",").map(s => s.trim()).filter(Boolean);

const TEMPLATES: Record<TemplateKey, (d: Record<string, unknown>) => { subject: string; html: string }> = {
  booking_inquiry_received: (d) => ({
    subject: `Recebemos o teu pedido (${d.event_title ?? "evento"})`,
    html: layout(`
      <h1>Pedido recebido</h1>
      <p>Olá ${escape(d.name)}, recebemos o teu pedido para <strong>${escape(d.event_title)}</strong> em ${escape(d.start_at)}.</p>
      <p>A nossa equipa vai analisar e enviar uma proposta em menos de 24h úteis.</p>`),
  }),
  proposal_sent: (d) => ({
    subject: `Nova proposta para ${d.event_title ?? "o teu evento"}`,
    html: layout(`
      <h1>Proposta pronta</h1>
      <p>Preparámos uma proposta no valor de <strong>${money(d.total)}</strong>.</p>
      <p><a class="cta" href="${escape(d.url)}">Ver proposta</a></p>`),
  }),
  booking_confirmed: (d) => ({
    subject: `Reserva confirmada — ${d.event_title}`,
    html: layout(`
      <h1>Tudo certo!</h1>
      <p>A tua reserva está <strong>confirmada</strong> para ${escape(d.start_at)}.</p>
      <p>Trucks: ${escape((d.trucks as string[] | undefined)?.join(", ") ?? "")}</p>`),
  }),
  booking_cancelled: (d) => ({
    subject: `Cancelamento — ${d.event_title}`,
    html: layout(`
      <h1>Reserva cancelada</h1>
      <p>Confirmamos o cancelamento. ${d.refund ? `Reembolso de ${money(d.refund)} será processado em 3-5 dias úteis.` : ""}</p>`),
  }),
  payment_received: (d) => ({
    subject: `Pagamento recebido — fatura ${d.invoice_number}`,
    html: layout(`
      <h1>Obrigado!</h1>
      <p>Pagamento de <strong>${money(d.amount)}</strong> recebido com sucesso.</p>
      <p><a class="cta" href="${escape(d.invoice_url)}">Descarregar fatura</a></p>`),
  }),
  review_request: (d) => ({
    subject: `Como foi o teu evento?`,
    html: layout(`
      <h1>Conta-nos como correu</h1>
      <p>Avalia os trucks que serviram o teu evento e ajuda outros clientes a escolherem melhor.</p>
      <p><a class="cta" href="${escape(d.url)}">Deixar review</a></p>`),
  }),
  contact_reply: (d) => ({
    subject: `Re: ${d.subject ?? "o teu contacto"}`,
    html: layout(`<p>${escape(d.message)}</p>`),
  }),
  newsletter_confirm: (d) => ({
    subject: `Confirma a tua subscrição`,
    html: layout(`
      <h1>Quase lá</h1>
      <p>Clica para confirmar a tua subscrição na newsletter Air F&amp;B.</p>
      <p><a class="cta" href="${escape(d.url)}">Confirmar</a></p>`),
  }),
};

const SUPABASE_URL              = Deno.env.get("SUPABASE_URL");
const SUPABASE_ANON_KEY         = Deno.env.get("SUPABASE_ANON_KEY");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

/** Validate the caller is either the service role OR a real authenticated user. */
async function authorize(req: Request): Promise<{ ok: true } | { ok: false; status: number; msg: string }> {
  const authz = req.headers.get("authorization") ?? "";
  if (!authz.toLowerCase().startsWith("bearer ")) {
    return { ok: false, status: 401, msg: "missing bearer token" };
  }
  const token = authz.slice(7).trim();
  if (!token) return { ok: false, status: 401, msg: "empty bearer token" };

  // Path 1: service role — exact match against the configured key.
  if (SUPABASE_SERVICE_ROLE_KEY && token === SUPABASE_SERVICE_ROLE_KEY) {
    return { ok: true };
  }

  // Path 2: ask the Supabase Auth API whether this is a valid user JWT.
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
    return { ok: false, status: 500, msg: "auth not configured" };
  }
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: SUPABASE_ANON_KEY, authorization: `Bearer ${token}` },
  });
  if (!res.ok) {
    return { ok: false, status: 401, msg: "invalid jwt" };
  }
  const user = await res.json().catch(() => null);
  if (!user?.id) {
    return { ok: false, status: 401, msg: "invalid user" };
  }
  return { ok: true };
}

Deno.serve(async (req) => {
  const pre = handlePreflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  if (!RESEND_API_KEY)       return json({ error: "RESEND_API_KEY not configured" }, 500);

  const authResult = await authorize(req);
  if (!authResult.ok) return json({ error: authResult.msg }, authResult.status);

  const body = (await req.json().catch(() => null)) as Payload | null;
  if (!body?.to || !body.template) return json({ error: "missing to/template" }, 400);
  if (ALLOWED.length && !ALLOWED.includes(body.template))
    return json({ error: `template not allowed: ${body.template}` }, 403);

  const tpl = TEMPLATES[body.template];
  if (!tpl) return json({ error: `unknown template: ${body.template}` }, 400);
  const { subject, html } = tpl(body.data ?? {});

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "authorization": `Bearer ${RESEND_API_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: Array.isArray(body.to) ? body.to : [body.to],
      reply_to: body.replyTo,
      subject: body.subject ?? subject,
      html,
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    return json({ error: "resend failed", detail: text.slice(0, 500) }, 502);
  }
  const data = await res.json();

  // best-effort audit log
  try {
    const supa = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    await supa.from("airfnb_audit_log").insert({
      action: `email.${body.template}`,
      entity: "email",
      diff: { to: body.to, subject: body.subject ?? subject, provider_id: data?.id },
    });
  } catch (_) { /* swallow */ }

  return json({ ok: true, id: data?.id });
});

// ---- helpers ----------------------------------------------------------------
function escape(s: unknown): string {
  return String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
}
function money(v: unknown): string {
  const n = Number(v);
  if (!isFinite(n)) return String(v ?? "");
  return new Intl.NumberFormat("pt-PT", { style: "currency", currency: "EUR" }).format(n);
}
function layout(inner: string): string {
  return `<!doctype html><html lang="pt"><body style="margin:0;padding:24px;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;background:#FFF6F2;color:#1A1A1A;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;margin:0 auto;background:#fff;border-radius:16px;box-shadow:0 6px 24px rgba(0,0,0,0.08);overflow:hidden;">
    <tr><td style="background:#FF6133;color:#fff;padding:22px 28px;font-family:'Bebas Neue',sans-serif;font-size:28px;letter-spacing:1px;">AIRF.B</td></tr>
    <tr><td style="padding:28px;line-height:1.55;font-size:15px;">${inner}</td></tr>
    <tr><td style="background:#1F5B65;color:#B0C4C8;padding:18px 28px;font-size:12px;">© ${new Date().getFullYear()} Air F&amp;B — todos os direitos reservados.</td></tr>
  </table>
  <style>.cta{display:inline-block;background:#FF4919;color:#fff !important;padding:12px 22px;border-radius:999px;text-decoration:none;font-weight:600;margin-top:8px;}</style>
</body></html>`;
}
