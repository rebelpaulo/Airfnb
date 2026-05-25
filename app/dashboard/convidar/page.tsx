import Link from "next/link";
import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { CopyButton } from "./CopyButton";

export const dynamic = "force-dynamic";

const APP_URL = process.env.APP_URL ?? process.env.NEXT_PUBLIC_APP_URL ?? "https://airfnb.vercel.app";

export default async function ConvidarPage() {
  const supa = await supabaseServer();
  const { data: { user } } = await supa.auth.getUser();
  if (!user) redirect("/login?next=/dashboard/convidar");

  const { data: profile } = await (supa as any)
    .from("airfnb_profiles")
    .select("referral_code, referrals_count, display_name")
    .eq("id", user.id)
    .maybeSingle();

  // The trigger fills referral_code on insert; old profiles backfilled by migration 30.
  const code = profile?.referral_code ?? "—";
  const link = `${APP_URL}/signup?ref=${code}`;

  const { data: redeemed } = await (supa as any)
    .from("airfnb_profiles")
    .select("display_name, created_at")
    .eq("referred_by", user.id)
    .order("created_at", { ascending: false })
    .limit(50);
  const redemptions: any[] = (redeemed as any[]) ?? [];

  return (
    <div className="dash" style={{ maxWidth: 720 }}>
      <h1 style={{ margin: 0 }}>Convidar amigos</h1>
      <p style={{ color: "var(--muted)", marginTop: 6 }}>
        Partilha o teu link e ajuda outros organizers / trucks a entrar.
      </p>

      <section style={{ marginTop: 24, background: "#fff", border: "1px solid var(--line)", borderRadius: 14, padding: 22 }}>
        <div style={{ fontSize: 13, color: "var(--muted)", letterSpacing: 0.4, textTransform: "uppercase", fontWeight: 700 }}>
          O teu código
        </div>
        <div style={{ fontFamily: "Bebas Neue, sans-serif", fontSize: 48, color: "var(--orange)", lineHeight: 1, marginTop: 4 }}>
          {code}
        </div>
        <div style={{ display: "flex", gap: 8, marginTop: 16, alignItems: "center", flexWrap: "wrap" }}>
          <input
            readOnly
            value={link}
            onFocus={(e) => e.currentTarget.select()}
            style={{ flex: 1, minWidth: 220, padding: "10px 14px", border: "1.5px solid var(--line)", borderRadius: 10, fontSize: 13, fontFamily: "monospace" }}
          />
          <CopyButton text={link} />
        </div>
        <div style={{ marginTop: 14, fontSize: 13, color: "var(--muted)" }}>
          <strong style={{ color: "var(--ink)" }}>{profile?.referrals_count ?? 0}</strong>
          {" "}{(profile?.referrals_count ?? 0) === 1 ? "pessoa" : "pessoas"} registaram-se com o teu link.
        </div>
      </section>

      {redemptions.length > 0 && (
        <section style={{ marginTop: 26 }}>
          <h2 style={{ margin: "0 0 12px", fontSize: 18 }}>Quem entrou pelo teu link</h2>
          <ul style={{ listStyle: "none", padding: 0, display: "grid", gap: 8 }}>
            {redemptions.map((r, i) => (
              <li key={i} style={{ display: "flex", justifyContent: "space-between", padding: "10px 14px", border: "1px solid var(--line)", borderRadius: 10, background: "#fff" }}>
                <span>{r.display_name ?? "—"}</span>
                <span style={{ color: "var(--muted)", fontSize: 13 }}>
                  {new Date(r.created_at).toLocaleDateString("pt-PT")}
                </span>
              </li>
            ))}
          </ul>
        </section>
      )}

      <p style={{ marginTop: 26, color: "var(--muted)", fontSize: 13 }}>
        <Link href="/dashboard/organizer" style={{ color: "var(--teal)" }}>← Voltar ao dashboard</Link>
      </p>
    </div>
  );
}
