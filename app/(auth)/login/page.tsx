"use client";
import { useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";

export default function LoginPage() {
  const router = useRouter();
  const sp = useSearchParams();
  // Only allow same-origin relative paths. Reject schemes, protocol-relative URLs,
  // backslashes, etc. — prevents open-redirect to phishing sites via ?next=https://evil.
  const rawNext = sp.get("next") ?? "/";
  const next = /^\/[^/\\]/.test(rawNext) || rawNext === "/" ? rawNext : "/";

  const [email, setEmail] = useState("");
  const [pwd, setPwd]   = useState("");
  const [err, setErr]   = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setErr(null);
    const supa = supabaseBrowser();
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
      {err && <div className="error">{err}</div>}
      <form onSubmit={onSubmit}>
        <div className="field">
          <label>Email</label>
          <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        </div>
        <div className="field">
          <label>Password</label>
          <input type="password" required value={pwd} onChange={(e) => setPwd(e.target.value)} />
        </div>
        <button className="btn-pill" style={{ width: "100%" }} disabled={busy} type="submit">
          {busy ? "A entrar…" : "Entrar"}
        </button>
      </form>
      <span className="switch-link">
        Ainda não tens conta? <Link href={`/signup?next=${encodeURIComponent(next)}`}>Regista-te</Link>
      </span>
    </div>
  );
}
