import Link from "next/link";
import { getDictionary } from "@/lib/i18n";

type Props = {
  /** what the user tried to do */
  intent: "add_truck" | "organize_event";
  /** the role they currently have */
  currentRole: "organizer" | "owner";
};

/**
 * Friendly block-page when a user with the wrong account type tries to access
 * a flow reserved for the other side of the marketplace. Roles are exclusive:
 * a single email cannot be both organizer and truck owner — they have to use
 * separate accounts.
 */
export async function WrongAccountType({ intent, currentRole }: Props) {
  const dict = await getDictionary();
  const t = dict.wrong_account_type;
  const isOrg = currentRole === "organizer";
  const title = intent === "add_truck" ? t.title_truck : t.title_event;
  const lead  = intent === "add_truck" ? t.lead_truck  : t.lead_event;
  // The `next` param contains its own query string (?as=...), so it must be
  // URL-encoded before being placed inside another query string — otherwise
  // the parser only captures up to the first unencoded `?` and the as= flag
  // silently drops.
  const cta = intent === "add_truck"
    ? { href: `/logout?next=${encodeURIComponent("/signup?as=truck")}`, label: t.cta_logout_truck }
    : { href: `/logout?next=${encodeURIComponent("/signup?as=organizer")}`, label: t.cta_logout_event };
  const back = isOrg
    ? { href: "/dashboard/organizer", label: t.back_organizer }
    : { href: "/dashboard/truck", label: t.back_truck };

  return (
    <div className="dash" style={{ maxWidth: 640 }}>
      <div style={{ marginTop: 24, padding: 28, background: "#fff", border: "1px solid var(--line)", borderRadius: 16 }}>
        <div style={{ fontSize: 13, color: "var(--muted)", letterSpacing: 0.4, textTransform: "uppercase", fontWeight: 700 }}>
          {t.eyebrow}
        </div>
        <h1 style={{ margin: "6px 0 12px", fontSize: 28 }}>{title}</h1>
        <p style={{ lineHeight: 1.6, color: "var(--ink)" }}>{lead}</p>
        <p style={{ fontSize: 13, color: "var(--muted)", marginTop: 12 }}>
          {t.reason}
        </p>
        <div style={{ display: "flex", gap: 10, marginTop: 20, flexWrap: "wrap" }}>
          <Link href={cta.href as any} className="btn-pill">{cta.label}</Link>
          <Link href={back.href as any} className="btn-pill outline"
                style={{ borderColor: "var(--line)", color: "var(--ink)" }}>
            {back.label}
          </Link>
        </div>
      </div>
    </div>
  );
}
