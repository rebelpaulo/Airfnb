"use client";
import { useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { ensureFbProfile } from "@/lib/auth/fb-membership";
import { OAuthButtons, OAUTH_ENABLED } from "@/components/auth/OAuthButtons";
import { useDict } from "@/components/DictProvider";

export default function LoginPage() {
  const dict = useDict();
  const t = dict.auth.login;
  const router = useRouter();
  const sp = useSearchParams();
  // Only allow same-origin relative paths. Reject schemes, protocol-relative URLs,
  // backslashes, etc. — prevents open-redirect to phishing sites via ?next=https://evil.
  const rawNext = sp.get("next") ?? "/";
  const next = /^\/[^/\\]/.test(rawNext) || rawNext === "/" ? rawNext : "/";

  const [mode, setMode] = useState<"password" | "magic">("password");
  const [email, setEmail] = useState("");
  const [pwd, setPwd]   = useState("");
  const [err, setErr]   = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setErr(null); setInfo(null);
    const supa = supabaseBrowser();

    if (mode === "magic") {
      const { error } = await supa.auth.signInWithOtp({
        email,
        options: {
          emailRedirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent(next)}`,
        },
      });
      setBusy(false);
      if (error) { setErr(error.message); return; }
      setInfo(t.magic_sent);
      return;
    }

    const { error } = await supa.auth.signInWithPassword({ email, password: pwd });
    if (error) { setBusy(false); setErr(error.message); return; }

    try {
      // Existing/imported profiles are returned unchanged. A user entering
      // F&B for the first time gets a role-null profile and must choose a
      // registration path explicitly.
      const profile = await ensureFbProfile(supa);
      setBusy(false);
      if (profile.role === null) {
        router.push("/registar");
        router.refresh();
        return;
      }
    } catch (membershipError) {
      setBusy(false);
      setErr(membershipError instanceof Error ? membershipError.message : String(membershipError));
      return;
    }
    router.push(next);
    router.refresh();
  }

  return (
    <div className="auth-card">
      <h1>{t.page_title}</h1>
      <p className="muted">{t.subtitle}</p>

      <OAuthButtons next={next} />

      {OAUTH_ENABLED && (
        <div role="separator" aria-orientation="horizontal"
             style={{ display: "flex", alignItems: "center", gap: 10, margin: "8px 0 14px", color: "var(--muted)", fontSize: 12 }}>
          <hr style={{ flex: 1, border: 0, borderTop: "1px solid var(--line)" }} />
          {t.separator_or}
          <hr style={{ flex: 1, border: 0, borderTop: "1px solid var(--line)" }} />
        </div>
      )}

      <div className="role-toggle" role="tablist" aria-label={t.method_aria}>
        <button type="button" role="tab" aria-selected={mode === "password"}
                className={mode === "password" ? "on" : ""} onClick={() => setMode("password")}>
          {t.tab_password}
        </button>
        <button type="button" role="tab" aria-selected={mode === "magic"}
                className={mode === "magic" ? "on" : ""} onClick={() => setMode("magic")}>
          {t.tab_magic}
        </button>
      </div>

      {err  && <div className="error">{err}</div>}
      {info && <div className="error" style={{ background: "#E8F5F1", color: "#1F5B65" }}>{info}</div>}

      <form onSubmit={onSubmit}>
        <div className="field">
          <label htmlFor="login-email">{t.email_label}</label>
          <input id="login-email" type="email" required value={email}
                 onChange={(e) => setEmail(e.target.value)} autoComplete="email" />
        </div>
        {mode === "password" && (
          <div className="field">
            <label htmlFor="login-pwd">{t.password_label}</label>
            <input id="login-pwd" type="password" required value={pwd}
                   onChange={(e) => setPwd(e.target.value)} autoComplete="current-password" />
          </div>
        )}
        <button className="btn-pill" style={{ width: "100%" }} disabled={busy} type="submit">
          {busy
            ? (mode === "magic" ? t.busy_magic : t.busy_password)
            : (mode === "magic" ? t.button_magic : t.button_password)}
        </button>
      </form>

      <span className="switch-link" style={{ marginTop: 10 }}>
        <Link href="/forgot-password">{t.forgot_link}</Link>
      </span>
      <span className="switch-link">
        {t.no_account} <Link href={`/signup?next=${encodeURIComponent(next)}`}>{t.signup_link}</Link>
      </span>
    </div>
  );
}
