"use client";
import { useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { OAuthButtons } from "@/components/auth/OAuthButtons";
import { useDict } from "@/components/DictProvider";

export default function SignupPage() {
  const dict = useDict();
  const t = dict.auth.signup;
  const router = useRouter();
  const sp = useSearchParams();
  const initialRole = (sp.get("as") === "truck" ? "owner" : "organizer") as "owner" | "organizer";
  // Only allow same-origin relative paths for ?next= to prevent open-redirect.
  const rawNext = sp.get("next") ?? "";
  const safeNext = /^\/[^/\\]/.test(rawNext) || rawNext === "/" ? rawNext : "";
  const next = safeNext || (initialRole === "owner" ? "/onboarding/truck" : "/onboarding/organizer");
  // Carry the referral code through the auth round-trip (email confirm +
  // OAuth). The callback reads ?ref= and credits the referrer atomically.
  const refCode = (sp.get("ref") ?? "").replace(/[^A-Za-z0-9]/g, "").slice(0, 16);

  const [role, setRole]   = useState<"organizer" | "owner">(initialRole);
  const [name, setName]   = useState("");
  const [email, setEmail] = useState("");
  const [pwd, setPwd]     = useState("");
  const [err, setErr]     = useState<string | null>(null);
  const [info, setInfo]   = useState<string | null>(null);
  const [busy, setBusy]   = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setErr(null); setInfo(null);
    const supa = supabaseBrowser();

    const { data, error } = await supa.auth.signUp({
      email,
      password: pwd,
      options: {
        data: { full_name: name, locale: "pt-PT" },
        emailRedirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent(next)}&as=${role}${refCode ? `&ref=${refCode}` : ""}`,
      },
    });
    if (error) { setBusy(false); setErr(error.message); return; }

    // If email confirmation is enabled in Supabase, signUp returns user but no session.
    if (!data.session) {
      setBusy(false);
      setInfo(t.confirm_email);
      return;
    }

    // We have a session — upgrade the role + name now while we still have the user id.
    if (data.user) {
      const { error: profileErr } = await (supa as any)
        .from("airfnb_profiles")
        .update({ role, full_name: name })
        .eq("id", data.user.id);
      if (profileErr) {
        setBusy(false);
        setErr(t.role_set_error);
        return;
      }
      // Apply referral attribution on the immediate-session path (the
      // /auth/callback handler covers the email-confirm + OAuth paths).
      if (refCode) {
        await (supa as any).rpc("airfnb_apply_referral", { p_code: refCode });
      }
    }
    setBusy(false);
    router.push(next);
    router.refresh();
  }

  return (
    <div className="auth-card">
      <h1>{t.page_title}</h1>
      <p className="muted">{t.subtitle}</p>

      <div className="role-toggle" role="tablist" aria-label={t.role_aria}>
        <button type="button" role="tab" aria-selected={role === "organizer"}
                className={role === "organizer" ? "on" : ""}
                onClick={() => setRole("organizer")}>
          {t.role_organizer}
        </button>
        <button type="button" role="tab" aria-selected={role === "owner"}
                className={role === "owner" ? "on" : ""}
                onClick={() => setRole("owner")}>
          {t.role_owner}
        </button>
      </div>

      <OAuthButtons next={next} asRole={role} refCode={refCode} />

      <div role="separator" aria-orientation="horizontal"
           style={{ display: "flex", alignItems: "center", gap: 10, margin: "8px 0 14px", color: "var(--muted)", fontSize: 12 }}>
        <hr style={{ flex: 1, border: 0, borderTop: "1px solid var(--line)" }} />
        {t.separator_or}
        <hr style={{ flex: 1, border: 0, borderTop: "1px solid var(--line)" }} />
      </div>

      {err  && <div className="error">{err}</div>}
      {info && <div className="error" style={{ background: "#E8F5F1", color: "#1F5B65" }}>{info}</div>}

      <form onSubmit={onSubmit}>
        <div className="field">
          <label htmlFor="signup-name">{t.name_label}</label>
          <input id="signup-name" required value={name}
                 onChange={(e) => setName(e.target.value)} autoComplete="name" />
        </div>
        <div className="field">
          <label htmlFor="signup-email">{t.email_label}</label>
          <input id="signup-email" type="email" required value={email}
                 onChange={(e) => setEmail(e.target.value)} autoComplete="email" />
        </div>
        <div className="field">
          <label htmlFor="signup-pwd">{t.password_label}</label>
          <input id="signup-pwd" type="password" required minLength={8}
                 value={pwd} onChange={(e) => setPwd(e.target.value)}
                 autoComplete="new-password" />
          <small style={{ color: "var(--muted)", fontSize: 12 }}>{t.password_hint}</small>
        </div>
        <button className="btn-pill" style={{ width: "100%" }} disabled={busy} type="submit">
          {busy ? t.busy_submit : t.button_submit}
        </button>
      </form>

      <span className="switch-link">
        {t.have_account} <Link href={`/login?next=${encodeURIComponent(next)}`}>{t.login_link}</Link>
      </span>
    </div>
  );
}
