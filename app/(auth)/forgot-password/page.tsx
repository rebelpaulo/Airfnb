"use client";
import { useState } from "react";
import Link from "next/link";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useDict } from "@/components/DictProvider";

export default function ForgotPasswordPage() {
  const dict = useDict();
  const t = dict.auth.forgot_password;
  const [email, setEmail] = useState("");
  const [busy, setBusy]   = useState(false);
  const [done, setDone]   = useState(false);
  const [err, setErr]     = useState<string | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setErr(null);
    const supa = supabaseBrowser();
    const { error } = await supa.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/reset-password`,
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    setDone(true);
  }

  return (
    <div className="auth-card">
      <h1>{t.page_title}</h1>
      <p className="muted">{t.subtitle}</p>

      {done ? (
        <div className="error" style={{ background: "#E8F5F1", color: "#1F5B65" }}>
          {t.sent_ok}
        </div>
      ) : (
        <>
          {err && <div className="error">{err}</div>}
          <form onSubmit={onSubmit}>
            <div className="field">
              <label htmlFor="forgot-email">{t.email_label}</label>
              <input
                id="forgot-email"
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                autoComplete="email"
              />
            </div>
            <button className="btn-pill" style={{ width: "100%" }} disabled={busy} type="submit">
              {busy ? t.busy_submit : t.button_submit}
            </button>
          </form>
        </>
      )}
      <span className="switch-link">
        <Link href="/login">{t.back_login}</Link>
      </span>
    </div>
  );
}
