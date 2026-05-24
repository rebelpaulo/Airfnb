"use client";
import { useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";

export default function SignupPage() {
  const router = useRouter();
  const sp = useSearchParams();
  const initialRole = (sp.get("as") === "truck" ? "owner" : "organizer") as "owner" | "organizer";
  const next = sp.get("next") ?? (initialRole === "owner" ? "/dashboard/truck" : "/dashboard/organizer");

  const [role, setRole]   = useState<"organizer" | "owner">(initialRole);
  const [name, setName]   = useState("");
  const [email, setEmail] = useState("");
  const [pwd, setPwd]     = useState("");
  const [err, setErr]     = useState<string | null>(null);
  const [busy, setBusy]   = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true); setErr(null);
    const supa = supabaseBrowser();

    const { data, error } = await supa.auth.signUp({
      email,
      password: pwd,
      options: { data: { full_name: name, locale: "pt-PT" } },
    });
    if (error) { setBusy(false); setErr(error.message); return; }

    // upgrade profile role (trigger created it with default 'organizer')
    if (data.user && role === "owner") {
      await supa.from("airfnb_profiles").update({ role: "owner", full_name: name }).eq("id", data.user.id);
    }
    setBusy(false);
    router.push(next);
    router.refresh();
  }

  return (
    <div className="auth-card">
      <h1>Criar conta</h1>
      <p className="muted">Escolhe o teu lado do marketplace.</p>

      <div className="role-toggle">
        <button type="button" className={role === "organizer" ? "on" : ""} onClick={() => setRole("organizer")}>
          Sou organizer
        </button>
        <button type="button" className={role === "owner" ? "on" : ""} onClick={() => setRole("owner")}>
          Tenho um Truck
        </button>
      </div>

      {err && <div className="error">{err}</div>}
      <form onSubmit={onSubmit}>
        <div className="field">
          <label>Nome</label>
          <input required value={name} onChange={(e) => setName(e.target.value)} />
        </div>
        <div className="field">
          <label>Email</label>
          <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        </div>
        <div className="field">
          <label>Password</label>
          <input type="password" required minLength={6} value={pwd} onChange={(e) => setPwd(e.target.value)} />
        </div>
        <button className="btn-pill" style={{ width: "100%" }} disabled={busy} type="submit">
          {busy ? "A criar conta…" : "Criar conta"}
        </button>
      </form>
      <span className="switch-link">
        Já tens conta? <Link href={`/login?next=${encodeURIComponent(next)}`}>Entra aqui</Link>
      </span>
    </div>
  );
}
