import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { money } from "@/lib/money";
import { getDictionary, getLocale } from "@/lib/i18n";
import { createLockFeeCheckout, markLockFeePaidDev } from "@/lib/payments/lock-fee.server";

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

  const { data: lockFee } = await (supa as any)
    .rpc("airfnb_supplier_lock_fee", { p_application: id })
    .maybeSingle();

  if (!lockFee) notFound();
  if (lockFee.lock_fee_status === "paid") {
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

    const result = await createLockFeeCheckout({ applicationId: id, user, supplier: supa });
    if (!result.ok) throw new Error(result.error);
    redirect(result.value.url);
  }

  async function devPay() {
    "use server";
    const dict = await getDictionary();
    const t = dict.dashboard.truck_lock_fee;
    const supa = await supabaseServer();
    const { data: { user } } = await supa.auth.getUser();
    if (!user) throw new Error(t.err_auth);
    const result = await markLockFeePaidDev({ applicationId: id, supplier: supa });
    if (!result.ok) throw new Error(result.error ?? t.err_dev_pay);
    redirect(`/dashboard/truck?paid=${id}`);
  }

  // The local payment control is never rendered in production; the flag
  // cannot override that boundary.
  const devPayOptIn =
    process.env.NODE_ENV !== "production" || process.env.ENABLE_DEV_PAY === "1";
  const showDev =
    process.env.NODE_ENV !== "production" &&
    !process.env.STRIPE_SECRET_KEY &&
    devPayOptIn;

  return (
    <div className="dash">
      <h1>{t.title}</h1>
      <div className="stat-strip">
        <div className="stat"><div className="label">{t.stat_event}</div><div className="value" style={{ fontSize: 18 }}>{lockFee.request_title}</div></div>
        <div className="stat"><div className="label">{t.stat_city}</div><div className="value" style={{ fontSize: 22 }}>{lockFee.city}</div></div>
        <div className="stat"><div className="label">{t.stat_total}</div><div className="value">{money(lockFee.amount)}</div></div>
        <div className="stat"><div className="label">{t.stat_deadline}</div><div className="value" style={{ fontSize: 18 }}>
          {new Date(lockFee.due_until).toLocaleString(dateLocale, { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" })}
        </div></div>
      </div>

      <div style={{ background: "#FFF6F2", padding: 22, borderRadius: 14, marginTop: 14, lineHeight: 1.7 }}>
        <p style={{ margin: 0 }}>
          <strong>{money(lockFee.platform_fee)}</strong>{t.breakdown_pre}<br />
          <strong>{money(lockFee.organizer_share)}</strong>{t.breakdown_mid_pre}{lockFee.deal_type}{t.breakdown_mid_post}<strong>{money(lockFee.organizer_share)}</strong>{t.breakdown_post}
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
