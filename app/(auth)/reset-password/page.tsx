"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";

export default function ResetPasswordPage() {
  const router = useRouter();
  const [pwd, setPwd]     = useState("");
  const [pwd2, setPwd2]   = useState("");
  const [busy, setBusy]   = useState(false);
  const [err, setErr]     = useState<string | null>(null);
  const [ready, setReady] = useState(false);

  // When users follow the recovery link, supabase-js emits PASSWORD_RECOVERY on session.
  useEffect(() => {
    const supa = supabaseBrowser();
    const { data: sub } = supa.auth.onAuthStateChange((event) => {
      if (event === "PASSWORD_RECOVERY" || event === "SIGNED_IN") setReady(true);
    });
    // also accept an already-active session (the link sets one)
    supa.auth.getUser().then(({ data }) => { if (data.user) setReady(true); });
    return () => { sub.subscription.unsubscribe(); };
  }, []);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (pwd !== pwd2)    { setErr("As passwords não coincidem."); return; }
    if (pwd.length < 8)  { setErr("A password deve ter pelo menos 8 caracteres."); return; }
    setBusy(true); setErr(null);
    const supa = supabaseBrowser();
    const { data: updRes, error } = await supa.auth.updateUser({ password: pwd });
    if (error) { setBusy(false); setErr(error.message); return; }

    // Route based on the user's role so truck owners land on their dashboard
    // rather than the organizer one.
    let target = "/dashboard/organizer";
    if (updRes?.user) {
      const { data: prof } = await (supa as any)
        .from("airfnb_profiles")
        .select("role")
        .eq("id", updRes.user.id)
        .maybeSingle();
      if (prof?.role === "owner") target = "/dashboard/truck";
    }
    setBusy(false);
    router.push(target);
    router.refresh();
  }

  return (
    <div className="auth-card">
      <h1>Nova password</h1>
      <p className="muted">Escolhe a nova password para a tua conta.</p>

      {!ready && (
        <div className="error" style={{ background: "#FFF6F2", color: "#8B1100" }}>
          Link inválido ou expirado. <a href="/forgot-password" style={{ color: "var(--orange)" }}>Pedir novo link</a>.
        </div>
      )}

      {err && <div className="error">{err}</div>}
      <form onSubmit={onSubmit}>
        <div className="field">
          <label htmlFor="new-pwd">Nova password</label>
          <input id="new-pwd" type="password" required minLength={8}
                 value={pwd} onChange={(e) => setPwd(e.target.value)}
                 autoComplete="new-password" />
        </div>
        <div className="field">
          <label htmlFor="new-pwd2">Repete a nova password</label>
          <input id="new-pwd2" type="password" required minLength={8}
                 value={pwd2} onChange={(e) => setPwd2(e.target.value)}
                 autoComplete="new-password" />
        </div>
        <button className="btn-pill" style={{ width: "100%" }} disabled={busy || !ready} type="submit">
          {busy ? "A guardar…" : "Guardar nova password"}
        </button>
      </form>
    </div>
  );
}
