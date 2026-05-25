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
  const enabled = confirm.trim().toUpperCase() === phrase && !busy;

  async function deleteAccount() {
    setBusy(true);
    setErr(null);
    try {
      const supa = supabaseBrowser();
      const { error } = await (supa as any).rpc("airfnb_self_delete");
      if (error) throw new Error(error.message);
      // Sign out — the row is gone but the session cookie isn't yet.
      await supa.auth.signOut();
      router.push("/?account_deleted=1");
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
        onClick={deleteAccount}
        disabled={!enabled}
        className="btn-pill"
        style={{ padding: "10px 22px", background: enabled ? "#8B1100" : "#C5A097", border: "none", color: "#fff", cursor: enabled ? "pointer" : "not-allowed" }}
      >
        {busy ? t.deleting : t.delete_permanently}
      </button>
    </div>
  );
}
