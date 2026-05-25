import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";
import { getDictionary, getLocale } from "@/lib/i18n";

function format(template: string, vars: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (_, k) => String(vars[k] ?? `{${k}}`));
}

export default async function LockFeePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;       // application_id
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect(`/login?next=/dashboard/truck/lock/${id}`);

  const dict = await getDictionary();
  const t = dict.dashboard.truck_lock_fee;
  const locale = await getLocale();
  const dateLocale = locale === "en" ? "en-US" : "pt-PT";

  const { data: app } = await (supa as any)
    .from("airfnb_applications")
    .select(`
      id, status, proposed_price, deal_type,
      airfnb_trucks ( id, name, owner_id ),
      airfnb_event_requests ( id, title, start_at, city ),
      airfnb_lock_fees ( id, amount, platform_fee, organizer_share, due_until, status )
    `)
    .eq("id", id)
    .maybeSingle();

  if (!app) notFound();
  if (app.airfnb_trucks?.owner_id !== user.id) redirect("/dashboard/truck");

  const lockFee = Array.isArray(app.airfnb_lock_fees) ? app.airfnb_lock_fees[0] : app.airfnb_lock_fees;
  if (!lockFee) notFound();
  if (lockFee.status === "paid") {
    return (
      <div className="dash">
        <h1>{t.confirmed_title}</h1>
        <div className="empty">
          {t.confirmed_body}
        </div>
      </div>
    );
  }

  async function checkout() {
    "use server";
    const dict = await getDictionary();
    const t = dict.dashboard.truck_lock_fee;
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error(t.err_auth);

    const res = await fetch(`${process.env.APP_URL}/api/stripe/checkout`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ application_id: id }),
      cache: "no-store",
    });
    const { url, error } = await res.json();
    if (error) throw new Error(error);
    redirect(url);
  }

  async function devPay() {
    "use server";
    const dict = await getDictionary();
    const t = dict.dashboard.truck_lock_fee;
    const token = process.env.DEV_PAY_TOKEN;
    const res = await fetch(`${process.env.APP_URL}/api/dev/mark-paid`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(token ? { "x-dev-pay-token": token } : {}),
      },
      body: JSON.stringify({ application_id: id }),
      cache: "no-store",
    });
    const r = await res.json();
    if (!r.ok) throw new Error(r.error ?? t.err_dev_pay);
    redirect(`/dashboard/truck?paid=${id}`);
  }

  // dev-pay button only outside production, OR explicit opt-in.
  const showDev =
    !process.env.STRIPE_SECRET_KEY &&
    (process.env.NODE_ENV !== "production" || process.env.ENABLE_DEV_PAY === "1");

  return (
    <div className="dash">
      <h1>{t.title}</h1>
      <div className="stat-strip">
        <div className="stat"><div className="label">{t.stat_event}</div><div className="value" style={{ fontSize: 18 }}>{app.airfnb_event_requests?.title}</div></div>
        <div className="stat"><div className="label">{t.stat_city}</div><div className="value" style={{ fontSize: 22 }}>{app.airfnb_event_requests?.city}</div></div>
        <div className="stat"><div className="label">{t.stat_total}</div><div className="value">{money(lockFee.amount)}</div></div>
        <div className="stat"><div className="label">{t.stat_deadline}</div><div className="value" style={{ fontSize: 18 }}>
          {new Date(lockFee.due_until).toLocaleString(dateLocale, { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" })}
        </div></div>
      </div>

      <div style={{ background: "#FFF6F2", padding: 22, borderRadius: 14, marginTop: 14, lineHeight: 1.7 }}>
        <p style={{ margin: 0 }}>
          <strong>{money(lockFee.platform_fee)}</strong>{t.breakdown_pre}<br />
          <strong>{money(lockFee.organizer_share)}</strong>{t.breakdown_mid_pre}{app.deal_type}{t.breakdown_mid_post}<strong>{money(lockFee.organizer_share)}</strong>{t.breakdown_post}
        </p>
      </div>

      <div style={{ display: "flex", gap: 12, alignItems: "center", marginTop: 22, flexWrap: "wrap" }}>
        {!showDev && (
          <form action={checkout}>
            <button className="btn-pill" type="submit">{format(t.pay_stripe_cta, { amount: money(lockFee.amount) })}</button>
          </form>
        )}
        {showDev && (
          <form action={devPay}>
            <button className="btn-pill" type="submit" style={{ background: "var(--teal)" }}>
              {t.mark_paid_dev}
            </button>
          </form>
        )}
        <Link href="/dashboard/truck" style={{ color: "var(--muted)" }}>{t.cancel}</Link>
        {showDev && (
          <small style={{ color: "var(--muted)", display: "block", flexBasis: "100%", marginTop: 6 }}>
            {t.dev_note_pre}<code>SUPABASE_SERVICE_ROLE_KEY</code>{t.dev_note_post}
          </small>
        )}
      </div>
    </div>
  );
}
