"use client";
import { useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

type Provider = "google" | "apple";

type Props = {
  /** path inside our app where the user should land after the OAuth round-trip */
  next?: string;
  /** role to upgrade profile to after first signup */
  asRole?: "organizer" | "owner";
  /** referral code to forward to the callback for attribution */
  refCode?: string;
};

const LABELS: Record<Provider, string> = {
  google: "Continuar com Google",
  apple:  "Continuar com Apple",
};

export function OAuthButtons({ next = "/", asRole, refCode }: Props) {
  const [busy, setBusy] = useState<Provider | null>(null);
  const [err, setErr]   = useState<string | null>(null);

  async function go(provider: Provider) {
    setBusy(provider); setErr(null);
    const supa = supabaseBrowser();
    const params = new URLSearchParams({ next });
    if (asRole) params.set("as", asRole);
    if (refCode) params.set("ref", refCode);
    const { error } = await supa.auth.signInWithOAuth({
      provider,
      options: {
        redirectTo: `${window.location.origin}/auth/callback?${params.toString()}`,
      },
    });
    if (error) {
      setBusy(null);
      setErr(error.message);
    }
    // on success the browser is being redirected, so no further state changes
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 8, marginBottom: 16 }}>
      {err && <div className="error">{err}</div>}
      {(["google", "apple"] as const).map((p) => (
        <button
          key={p}
          type="button"
          onClick={() => go(p)}
          disabled={busy !== null}
          aria-label={LABELS[p]}
          style={{
            display: "flex", alignItems: "center", justifyContent: "center", gap: 10,
            padding: "10px 14px",
            border: "1.5px solid var(--line)", borderRadius: "var(--radius-md)",
            background: "#fff", color: "var(--ink)",
            font: "inherit", fontWeight: 600, fontSize: 14,
            cursor: busy ? "wait" : "pointer",
          }}
        >
          <ProviderIcon provider={p} />
          {busy === p ? "A redirecionar…" : LABELS[p]}
        </button>
      ))}
    </div>
  );
}

function ProviderIcon({ provider }: { provider: Provider }) {
  if (provider === "google") {
    return (
      <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true">
        <path d="M17.64 9.2c0-.64-.06-1.25-.16-1.84H9v3.49h4.84a4.14 4.14 0 01-1.8 2.72v2.26h2.91c1.7-1.57 2.69-3.88 2.69-6.63z" fill="#4285F4"/>
        <path d="M9 18c2.43 0 4.47-.81 5.96-2.18l-2.91-2.26c-.81.54-1.84.86-3.05.86-2.35 0-4.34-1.59-5.05-3.71H.96v2.33A9 9 0 009 18z" fill="#34A853"/>
        <path d="M3.95 10.71A5.4 5.4 0 013.66 9c0-.59.1-1.17.29-1.71V4.96H.96A9.01 9.01 0 000 9c0 1.45.35 2.83.96 4.04l2.99-2.33z" fill="#FBBC05"/>
        <path d="M9 3.58c1.32 0 2.51.46 3.44 1.35l2.58-2.58A9 9 0 009 0 9 9 0 00.96 4.96l2.99 2.33C4.66 5.17 6.65 3.58 9 3.58z" fill="#EA4335"/>
      </svg>
    );
  }
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" aria-hidden="true">
      <path d="M13.94 9.62c-.02-2.15 1.76-3.18 1.84-3.23-1-1.46-2.55-1.66-3.1-1.68-1.32-.14-2.58.78-3.25.78-.68 0-1.7-.76-2.81-.74-1.45.02-2.79.84-3.53 2.13-1.5 2.6-.38 6.45 1.08 8.55.72 1.03 1.57 2.19 2.69 2.15 1.08-.04 1.49-.7 2.79-.7 1.3 0 1.66.7 2.81.68 1.16-.02 1.9-1.05 2.6-2.09.83-1.2 1.17-2.37 1.18-2.43-.03-.01-2.27-.87-2.3-3.42zM11.86 3.4c.59-.71.99-1.71.88-2.7-.85.03-1.88.57-2.49 1.28-.55.63-1.03 1.64-.9 2.62.95.07 1.92-.49 2.51-1.2z" fill="#000"/>
    </svg>
  );
}
