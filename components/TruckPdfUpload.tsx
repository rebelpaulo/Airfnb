"use client";
import { useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useDict } from "@/components/DictProvider";

// Inline placeholder formatter (kept local because lib/i18n imports
// next/headers, which can't be bundled into client components).
function format(template: string, vars: Record<string, string | number>): string {
  return Object.entries(vars).reduce(
    (out, [k, v]) => out.replace(`{${k}}`, String(v)),
    template,
  );
}

const BUCKET = "airfnb-documents";

export type DocKind = "asae" | "comercial" | "financas" | "outros";

type Props = {
  truckId: string;
  kind: DocKind;
  label: string;
  initialUrl?: string | null;
  /** if set, the document expires on this ISO date (YYYY-MM-DD) */
  initialExpires?: string | null;
  /** called after a successful upload (or removal) */
  onChange?: (url: string | null) => void;
  /** max file size in MB (default 8) */
  maxMb?: number;
};

/**
 * Single-PDF drop zone for one of the 4 wizard document slots. Uploads to
 * the private `airfnb-documents` bucket at `<truck_id>/<kind>-<ts>.pdf`,
 * then upserts a row in airfnb_truck_documents (one row per truck+kind).
 */
export function TruckPdfUpload({
  truckId, kind, label, initialUrl, initialExpires, onChange, maxMb = 8,
}: Props) {
  const dict = useDict();
  const t = dict.forms.truck_pdf_upload;
  const inputRef = useRef<HTMLInputElement>(null);
  const [url, setUrl] = useState<string | null>(initialUrl ?? null);
  const [expires, setExpires] = useState<string>(initialExpires ?? "");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function pickFile(file: File) {
    setErr(null);
    if (file.type !== "application/pdf") {
      setErr(t.err_not_pdf);
      return;
    }
    if (file.size > maxMb * 1024 * 1024) {
      setErr(format(t.err_too_large, { maxMb }));
      return;
    }
    setBusy(true);
    try {
      const supa = supabaseBrowser();
      const path = `${truckId}/${kind}-${Date.now()}.pdf`;
      const { error: upErr } = await supa.storage.from(BUCKET).upload(path, file, {
        contentType: "application/pdf",
      });
      if (upErr) throw new Error(upErr.message);
      // Bucket is private — store the object PATH only. The reader (admin or
      // owner) generates a signed URL on demand. Saving `getPublicUrl()` would
      // give a 404 link to any future consumer that hits it.
      // Sign a short-lived URL just for the just-uploaded preview state.
      const { data: signed } = await supa.storage.from(BUCKET).createSignedUrl(path, 60 * 60);

      // one row per (truck, kind) — delete then insert. Avoids needing a
      // unique constraint that the original schema doesn't declare.
      await (supa as any).from("airfnb_truck_documents").delete().match({ truck_id: truckId, kind });
      const { error: insErr } = await (supa as any).from("airfnb_truck_documents").insert({
        truck_id: truckId,
        kind,
        url: path,                       // object key, not a URL
        expires_at: expires || null,
      });
      if (insErr) throw new Error(insErr.message);

      // local preview uses the signed URL (it's owner viewing right after upload)
      setUrl(signed?.signedUrl ?? null);
      onChange?.(signed?.signedUrl ?? null);
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function saveExpires(value: string) {
    setExpires(value);
    if (!url) return;
    const supa = supabaseBrowser();
    await (supa as any).from("airfnb_truck_documents")
      .update({ expires_at: value || null })
      .match({ truck_id: truckId, kind });
  }

  async function remove() {
    const supa = supabaseBrowser();
    const { error } = await (supa as any).from("airfnb_truck_documents")
      .delete().match({ truck_id: truckId, kind });
    if (error) { setErr(error.message); return; }
    setUrl(null);
    onChange?.(null);
  }

  return (
    <div
      onClick={() => !url && inputRef.current?.click()}
      onDragOver={(e) => { if (!url) e.preventDefault(); }}
      onDrop={(e) => {
        if (url) return;
        e.preventDefault();
        const f = e.dataTransfer.files?.[0];
        if (f) pickFile(f);
      }}
      style={{
        border: "2px dashed var(--line)", borderRadius: 12, padding: 16,
        background: url ? "#F1FBF5" : "#FAFAFA",
        cursor: url ? "default" : busy ? "wait" : "pointer",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
        <span className="material-symbols-outlined" style={{ fontSize: 28, color: url ? "#10A37F" : "var(--orange)" }}>
          {url ? "task" : "upload_file"}
        </span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontWeight: 700, color: "var(--ink)" }}>{label}</div>
          <div style={{ fontSize: 12, color: "var(--muted)" }}>
            {busy ? t.loading : url ? t.uploaded : format(t.size_hint, { maxMb })}
          </div>
        </div>
        {url && (
          <button type="button" onClick={remove}
            style={{ background: "transparent", border: "1px solid var(--line)", padding: "4px 10px", borderRadius: 8, cursor: "pointer", fontSize: 12 }}>
            {t.replace}
          </button>
        )}
      </div>
      {url && (
        <div style={{ marginTop: 10, display: "flex", alignItems: "center", gap: 8 }}>
          <label style={{ fontSize: 12, color: "var(--muted)" }}>{t.expires_label}</label>
          <input
            type="date"
            value={expires}
            onChange={(e) => saveExpires(e.target.value)}
            style={{ border: "1px solid var(--line)", borderRadius: 6, padding: "4px 8px", fontSize: 13 }}
          />
        </div>
      )}
      <input
        ref={inputRef}
        type="file"
        accept="application/pdf"
        style={{ display: "none" }}
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) pickFile(f);
          if (inputRef.current) inputRef.current.value = "";
        }}
      />
      {err && <div style={{ color: "#8B1100", marginTop: 8, fontSize: 13 }}>{err}</div>}
    </div>
  );
}
