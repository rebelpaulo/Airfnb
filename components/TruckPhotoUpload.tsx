"use client";
import { useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useDict } from "@/components/DictProvider";

// Inline placeholder formatter (kept local because lib/i18n imports
// next/headers, which can't be bundled into client components).
// Substitutes `{key}` tokens in `template` with stringified values.
function format(template: string, vars: Record<string, string | number>): string {
  return Object.entries(vars).reduce(
    (out, [k, v]) => out.replace(`{${k}}`, String(v)),
    template,
  );
}

const BUCKET = "airfnb-truck-images";

// Matches public.airfnb_truck_image_kind in migration airfnb_43. Kept in
// the order we surface to the user (truck first because that's the photo
// we WANT them to upload first — the gallery_urls view orders by this).
const KINDS = ["truck", "food", "venue", "team", "other"] as const;
type Kind = typeof KINDS[number];

type Photo = { id?: string; url: string; isCover?: boolean; kind?: Kind };

type Props = {
  truckId: string;
  initial?: Photo[];
  /** maximum number of photos to keep in the gallery */
  max?: number;
  /** called after every successful upload with the new full list */
  onChange?: (photos: Photo[]) => void;
};

/**
 * Multi-file gallery uploader for a truck. Compresses each image to ≤2MB
 * client-side, writes to storage at `<truck_id>/<timestamp>.<ext>`, then
 * inserts the row in airfnb_truck_images. The first uploaded photo is
 * automatically marked as the cover.
 */
export function TruckPhotoUpload({ truckId, initial = [], max = 12, onChange }: Props) {
  const dict = useDict();
  const t = dict.forms.truck_photo_upload;
  const inputRef = useRef<HTMLInputElement>(null);
  const [photos, setPhotos] = useState<Photo[]>(initial);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  // Kind chosen for the NEXT upload. Defaults to "truck" when the gallery
  // is empty (so the first photo organizers see is the truck itself) and
  // flips to "food" once at least one truck-kind photo exists. Owner can
  // override before dropping files.
  const initialKind: Kind = initial.some((p) => p.kind === "truck") ? "food" : "truck";
  const [pendingKind, setPendingKind] = useState<Kind>(initialKind);

  async function handleFiles(files: FileList) {
    setErr(null);
    setBusy(true);
    try {
      const supa = supabaseBrowser();
      const next: Photo[] = [...photos];
      for (const file of Array.from(files)) {
        if (next.length >= max) break;
        if (!file.type.startsWith("image/")) continue;
        const blob = await compressTo(file, 2, t.err_too_large);
        const ext = mimeToExt(blob.type) || "jpg";
        const path = `${truckId}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;
        const { error: upErr } = await supa.storage.from(BUCKET).upload(path, blob, {
          contentType: blob.type || "image/jpeg",
        });
        if (upErr) throw new Error(upErr.message);
        const { data: { publicUrl } } = supa.storage.from(BUCKET).getPublicUrl(path);
        const isFirst = next.length === 0;
        const { data: row, error: insErr } = await (supa as any)
          .from("airfnb_truck_images")
          .insert({
            truck_id: truckId,
            url: publicUrl,
            is_cover: isFirst,
            sort_order: next.length,
            kind: pendingKind,
          })
          .select("id, url, is_cover, kind")
          .single();
        if (insErr) throw new Error(insErr.message);
        next.push({ id: row.id, url: row.url, isCover: row.is_cover, kind: row.kind });
        setPhotos([...next]);
      }
      // Auto-flip the kind picker after the first truck photo lands —
      // subsequent uploads default to food, which matches the gallery
      // ordering convention. Owner can flip back manually.
      if (pendingKind === "truck" && next.some((p) => p.kind === "truck")) {
        setPendingKind("food");
      }
      onChange?.(next);
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function setCover(photoId: string) {
    const supa = supabaseBrowser();
    // unset all, set this one — two updates is fine for ≤12 photos
    await (supa as any).from("airfnb_truck_images").update({ is_cover: false }).eq("truck_id", truckId);
    await (supa as any).from("airfnb_truck_images").update({ is_cover: true }).eq("id", photoId);
    const next = photos.map((p) => ({ ...p, isCover: p.id === photoId }));
    setPhotos(next);
    onChange?.(next);
  }

  async function setKind(photoId: string, kind: Kind) {
    const supa = supabaseBrowser();
    // Belt-and-braces: scope the update to (id, truck_id). RLS already
    // gates owners to their own trucks, but a narrowed predicate makes
    // the intent explicit and stops a stale id from ever touching a
    // sibling truck's row (e.g. if the parent component recycles photo
    // objects across truck switches).
    const { error } = await (supa as any)
      .from("airfnb_truck_images")
      .update({ kind })
      .eq("id", photoId)
      .eq("truck_id", truckId);
    if (error) {
      setErr(error.message);
      return;
    }
    const next = photos.map((p) => (p.id === photoId ? { ...p, kind } : p));
    setPhotos(next);
    onChange?.(next);
  }

  async function remove(photoId: string) {
    const supa = supabaseBrowser();
    const { error } = await (supa as any).from("airfnb_truck_images").delete().eq("id", photoId);
    if (error) {
      setErr(error.message);
      return;
    }
    const next = photos.filter((p) => p.id !== photoId);
    // if we deleted the cover, promote the first remaining photo
    if (!next.some((p) => p.isCover) && next[0]?.id) {
      await (supa as any).from("airfnb_truck_images").update({ is_cover: true }).eq("id", next[0].id);
      next[0] = { ...next[0], isCover: true };
    }
    setPhotos(next);
    onChange?.(next);
  }

  const kindLabel = (k: Kind): string =>
    ((t as Record<string, string>)[`kind_${k}`] ?? k);

  return (
    <div>
      {/* Kind chips control the type tagged onto the NEXT upload(s). They
          live above the dropzone so the choice is unambiguous in the
          moment of dragging files in. */}
      <div style={{ display: "flex", alignItems: "center", flexWrap: "wrap", gap: 8, marginBottom: 10 }}>
        <span style={{ fontSize: 13, color: "var(--muted)", fontWeight: 600 }}>
          {(t as Record<string, string>).kind_label ?? "Próximas fotos:"}
        </span>
        {KINDS.map((k) => {
          const active = pendingKind === k;
          return (
            <button
              type="button"
              key={k}
              onClick={() => setPendingKind(k)}
              aria-pressed={active}
              style={{
                padding: "5px 12px",
                borderRadius: 999,
                border: "1px solid",
                borderColor: active ? "var(--orange)" : "var(--line)",
                background: active ? "var(--orange)" : "#fff",
                color: active ? "#fff" : "var(--ink)",
                fontSize: 12,
                fontWeight: active ? 700 : 500,
                cursor: "pointer",
                fontFamily: "inherit",
              }}
            >
              {kindLabel(k)}
            </button>
          );
        })}
      </div>
      <div
        onClick={() => inputRef.current?.click()}
        onDragOver={(e) => { e.preventDefault(); }}
        onDrop={(e) => {
          e.preventDefault();
          if (e.dataTransfer.files?.length) handleFiles(e.dataTransfer.files);
        }}
        style={{
          border: "2px dashed var(--line)", borderRadius: 14,
          padding: 28, textAlign: "center", cursor: busy ? "wait" : "pointer",
          background: "#FAFAFA", color: "var(--muted)",
        }}
      >
        <span className="material-symbols-outlined" style={{ fontSize: 32, color: "var(--orange)" }}>
          add_photo_alternate
        </span>
        <div style={{ marginTop: 6, fontWeight: 600, color: "var(--ink)" }}>
          {busy ? t.loading : t.add_photos}
        </div>
        <div style={{ fontSize: 13 }}>{format(t.hint, { max })}</div>
      </div>
      <input
        ref={inputRef}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        multiple
        style={{ display: "none" }}
        onChange={(e) => {
          if (e.target.files?.length) handleFiles(e.target.files);
          if (inputRef.current) inputRef.current.value = "";
        }}
      />
      {err && <div style={{ color: "#8B1100", marginTop: 8, fontSize: 13 }}>{err}</div>}

      {photos.length > 0 && (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(140px, 1fr))", gap: 10, marginTop: 14 }}>
          {photos.map((p) => (
            <div key={p.id ?? p.url} style={{ position: "relative", aspectRatio: "4/3", borderRadius: 10, overflow: "hidden", border: "1px solid var(--line)" }}>
              <img src={p.url} alt="" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
              {p.isCover && (
                <span style={{
                  position: "absolute", top: 6, left: 6, background: "var(--orange)", color: "#fff",
                  fontSize: 11, padding: "2px 8px", borderRadius: 999, fontWeight: 700, letterSpacing: 0.4, textTransform: "uppercase",
                }}>{t.cover_badge}</span>
              )}
              {p.id && (
                // Render the editor for every persisted photo, even if the
                // initial fetch came back without a kind (legacy rows that
                // predate migration airfnb_43). Fallback to 'other' so the
                // <select> has a defined value and the owner can pick the
                // correct kind.
                <select
                  value={p.kind ?? "other"}
                  onChange={(e) => setKind(p.id!, e.target.value as Kind)}
                  aria-label={(t as Record<string, string>).kind_label ?? "Tipo de foto"}
                  style={{
                    position: "absolute", top: 6, right: 6,
                    background: "rgba(0,0,0,0.65)", color: "#fff",
                    border: 0, borderRadius: 999,
                    fontSize: 11, padding: "2px 8px", fontFamily: "inherit",
                    cursor: "pointer", appearance: "none",
                  }}
                >
                  {KINDS.map((k) => (
                    <option key={k} value={k} style={{ color: "#000" }}>
                      {kindLabel(k)}
                    </option>
                  ))}
                </select>
              )}
              {p.id && (
                <div style={{ position: "absolute", bottom: 0, left: 0, right: 0, display: "flex", justifyContent: "space-between", background: "linear-gradient(transparent,rgba(0,0,0,0.6))", padding: 6 }}>
                  {!p.isCover && (
                    <button type="button" onClick={() => setCover(p.id!)} style={{ background: "rgba(255,255,255,0.9)", border: "none", borderRadius: 6, padding: "3px 8px", fontSize: 11, cursor: "pointer" }}>
                      {t.set_cover}
                    </button>
                  )}
                  <button type="button" onClick={() => remove(p.id!)} style={{ marginLeft: "auto", background: "rgba(255,255,255,0.9)", border: "none", borderRadius: 6, padding: "3px 8px", fontSize: 11, cursor: "pointer", color: "#8B1100" }}>
                    {t.delete}
                  </button>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function mimeToExt(mime: string): string {
  switch (mime) {
    case "image/jpeg": case "image/jpg": return "jpg";
    case "image/png":                    return "png";
    case "image/webp":                   return "webp";
    case "image/gif":                    return "gif";
    case "image/avif":                   return "avif";
    default:                             return "";
  }
}

async function compressTo(file: File, maxMb: number, tooLargeTemplate: string): Promise<Blob> {
  const cap = maxMb * 1024 * 1024;
  let blob = await reencode(file, 1600, 0.85);
  if (blob.size <= cap) return blob;
  blob = await reencode(file, 1200, 0.78);
  if (blob.size <= cap) return blob;
  blob = await reencode(file, 900, 0.7);
  // After the most aggressive pass we still surface the cap rather than
  // silently uploading an oversize image — RLS/storage limits would fail later
  // anyway, but the owner deserves an immediate, actionable error.
  if (blob.size > cap) {
    throw new Error(format(tooLargeTemplate, {
      size: (blob.size / 1024 / 1024).toFixed(1),
      maxMb,
    }));
  }
  return blob;
}

function reencode(file: File, maxDim: number, quality: number): Promise<Blob> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error("read failed"));
    reader.onload = () => {
      const img = new Image();
      img.onerror = () => reject(new Error("decode failed"));
      img.onload = () => {
        const ratio = Math.min(maxDim / img.width, maxDim / img.height, 1);
        const w = Math.round(img.width * ratio);
        const h = Math.round(img.height * ratio);
        const canvas = document.createElement("canvas");
        canvas.width = w; canvas.height = h;
        const ctx = canvas.getContext("2d");
        if (!ctx) return reject(new Error("no canvas context"));
        ctx.drawImage(img, 0, 0, w, h);
        canvas.toBlob(
          (b) => (b ? resolve(b) : reject(new Error("encode failed"))),
          "image/jpeg",
          quality,
        );
      };
      img.src = reader.result as string;
    };
    reader.readAsDataURL(file);
  });
}
