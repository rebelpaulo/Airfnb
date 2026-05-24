"use client";
import { useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { OAuthButtons } from "@/components/auth/OAuthButtons";

export default function LoginPage() {
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
      setInfo("Email enviado. Clica no link para entrares.");
      return;
    }

    const { error } = await supa.auth.signInWithPassword({ email, password: pwd });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    router.push(next);
    router.refresh();
  }

  return (
    <div className="auth-card">
      <h1>Entrar</h1>
      <p className="muted">Acede à tua conta Air F&amp;B.</p>

      <OAuthButtons next={next} />

      <div role="separator" aria-orientation="horizontal"
           style={{ display: "flex", alignItems: "center", gap: 10, margin: "8px 0 14px", color: "var(--muted)", fontSize: 12 }}>
        <hr style={{ flex: 1, border: 0, borderTop: "1px solid var(--line)" }} />
        OU
        <hr style={{ flex: 1, border: 0, borderTop: "1px solid var(--line)" }} />
      </div>

      <div className="role-toggle" role="tablist" aria-label="Método de login">
        <button type="button" role="tab" aria-selected={mode === "password"}
                className={mode === "password" ? "on" : ""} onClick={() => setMode("password")}>
          Password
        </button>
        <button type="button" role="tab" aria-selected={mode === "magic"}
                className={mode === "magic" ? "on" : ""} onClick={() => setMode("magic")}>
          Magic link
        </button>
      </div>

      {err  && <div className="error">{err}</div>}
      {info && <div className="error" style={{ background: "#E8F5F1", color: "#1F5B65" }}>{info}</div>}

      <form onSubmit={onSubmit}>
        <div className="field">
          <label htmlFor="login-email">Email</label>
          <input id="login-email" type="email" required value={email}
                 onChange={(e) => setEmail(e.target.value)} autoComplete="email" />
        </div>
        {mode === "password" && (
          <div className="field">
            <label htmlFor="login-pwd">Password</label>
            <input id="login-pwd" type="password" required value={pwd}
                   onChange={(e) => setPwd(e.target.value)} autoComplete="current-password" />
          </div>
        )}
        <button className="btn-pill" style={{ width: "100%" }} disabled={busy} type="submit">
          {busy
            ? (mode === "magic" ? "A enviar email…" : "A entrar…")
            : (mode === "magic" ? "Enviar link mágico" : "Entrar")}
        </button>
      </form>

      <span className="switch-link" style={{ marginTop: 10 }}>
        <Link href="/forgot-password">Esqueceste a password?</Link>
      </span>
      <span className="switch-link">
        Ainda não tens conta? <Link href={`/signup?next=${encodeURIComponent(next)}`}>Regista-te</Link>
      </span>
    </div>
  );
}
