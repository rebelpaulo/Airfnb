"use client";
import { useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

const BUCKET = "airfnb-truck-images";

type Photo = { id?: string; url: string; isCover?: boolean };

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
  const inputRef = useRef<HTMLInputElement>(null);
  const [photos, setPhotos] = useState<Photo[]>(initial);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function handleFiles(files: FileList) {
    setErr(null);
    setBusy(true);
    try {
      const supa = supabaseBrowser();
      const next: Photo[] = [...photos];
      for (const file of Array.from(files)) {
        if (next.length >= max) break;
        if (!file.type.startsWith("image/")) continue;
        const blob = await compressTo(file, 2);
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
          .insert({ truck_id: truckId, url: publicUrl, is_cover: isFirst, sort_order: next.length })
          .select("id, url, is_cover")
          .single();
        if (insErr) throw new Error(insErr.message);
        next.push({ id: row.id, url: row.url, isCover: row.is_cover });
        setPhotos([...next]);
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

  return (
    <div>
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
          {busy ? "A carregar…" : "Adicionar fotografias"}
        </div>
        <div style={{ fontSize: 13 }}>Arrasta para aqui ou clica. PNG, JPG ou WebP. Máx {max} fotos.</div>
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
                }}>Capa</span>
              )}
              {p.id && (
                <div style={{ position: "absolute", bottom: 0, left: 0, right: 0, display: "flex", justifyContent: "space-between", background: "linear-gradient(transparent,rgba(0,0,0,0.6))", padding: 6 }}>
                  {!p.isCover && (
                    <button type="button" onClick={() => setCover(p.id!)} style={{ background: "rgba(255,255,255,0.9)", border: "none", borderRadius: 6, padding: "3px 8px", fontSize: 11, cursor: "pointer" }}>
                      Capa
                    </button>
                  )}
                  <button type="button" onClick={() => remove(p.id!)} style={{ marginLeft: "auto", background: "rgba(255,255,255,0.9)", border: "none", borderRadius: 6, padding: "3px 8px", fontSize: 11, cursor: "pointer", color: "#8B1100" }}>
                    Apagar
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

async function compressTo(file: File, maxMb: number): Promise<Blob> {
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
    throw new Error(`Imagem demasiado grande mesmo após compressão (${(blob.size / 1024 / 1024).toFixed(1)}MB > ${maxMb}MB). Reduz a resolução antes de carregar.`);
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
