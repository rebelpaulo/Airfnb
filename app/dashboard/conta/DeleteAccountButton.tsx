"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useDict } from "@/components/DictProvider";

export function DeleteAccountButton() {
  const dict = useDict();
  const t = dict.dashboard.shared_delete_account;
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [err, setErr]   = useState<string | null>(null);
  const [confirm, setConfirm] = useState("");

  const phrase = t.confirm_phrase;
  // Normalize both sides — if a locale ever defines the phrase in mixed/lower
  // case, the comparison still works. Uppercasing only the input would deadlock.
  const enabled =
    confirm.trim().toLocaleUpperCase() === phrase.trim().toLocaleUpperCase() && !busy;

  async function deleteFbMembership() {
    setBusy(true);
    setErr(null);
    try {
      const supa = supabaseBrowser();
      const response = await fetch("/api/me/fb-membership", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "same-origin",
      });
      if (!response.ok) {
        const body = await response.json().catch(() => null);
        throw new Error(body?.error ?? "membership deletion failed");
      }
      // The shared Tailor Auth identity remains. End only this browser session;
      // a global sign-out would revoke sessions belonging to the shared account.
      const { error: signOutError } = await supa.auth.signOut({ scope: "local" });
      if (signOutError) throw new Error(signOutError.message);
      router.replace("/?fb_membership_deleted=1");
      router.refresh();
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
      setBusy(false);
    }
  }

  return (
    <div style={{ marginTop: 14, display: "grid", gap: 10 }}>
      <label style={{ display: "grid", gap: 6, fontSize: 13 }}>
        <span>{t.confirm_pre}<code>{phrase}</code></span>
        <input
          value={confirm}
          onChange={(e) => setConfirm(e.target.value)}
          placeholder={phrase}
          style={{ padding: "10px 14px", border: "1.5px solid var(--line)", borderRadius: 10, fontSize: 14, fontFamily: "monospace" }}
        />
      </label>
      {err && <div style={{ color: "#8B1100", fontSize: 13 }}>{err}</div>}
      <button
        type="button"
        onClick={deleteFbMembership}
        disabled={!enabled}
        className="btn-pill"
        style={{ padding: "10px 22px", background: enabled ? "#8B1100" : "#C5A097", border: "none", color: "#fff", cursor: enabled ? "pointer" : "not-allowed" }}
      >
        {busy ? t.deleting : t.delete_permanently}
      </button>
    </div>
  );
}
