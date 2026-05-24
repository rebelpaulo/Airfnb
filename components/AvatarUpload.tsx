"use client";
import { useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

type Props = {
  userId: string;
  initialUrl?: string | null;
  /** called with the new public URL after upload (and optional profile update) */
  onUploaded?: (url: string) => void;
  /** if true, this component also writes airfnb_profiles.avatar_url for the user */
  persistOnProfile?: boolean;
  /** if true, file is compressed client-side before upload */
  compress?: boolean;
  /** max file size in MB (default 2) */
  maxMb?: number;
  size?: number;
};

const BUCKET = "airfnb-avatars";

export function AvatarUpload({
  userId, initialUrl, onUploaded, persistOnProfile = true,
  compress = true, maxMb = 2, size = 96,
}: Props) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [url, setUrl] = useState<string | null>(initialUrl ?? null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function pickFile(file: File) {
    setErr(null);
    if (!file.type.startsWith("image/")) {
      setErr("Tem de ser uma imagem.");
      return;
    }
    setBusy(true);
    try {
      const blob = compress ? await compressTo(file, maxMb) : file;
      if (blob.size > maxMb * 1024 * 1024) {
        throw new Error(`Imagem muito grande (>${maxMb}MB). Tenta uma mais pequena.`);
      }
      const ext = (file.name.split(".").pop() ?? "jpg").toLowerCase().slice(0, 5);
      const path = `${userId}/avatar-${Date.now()}.${ext}`;

      const supa = supabaseBrowser();
      const { error: upErr } = await supa.storage.from(BUCKET).upload(path, blob, {
        upsert: true, contentType: blob.type || "image/jpeg",
      });
      if (upErr) throw new Error(upErr.message);

      const { data: { publicUrl } } = supa.storage.from(BUCKET).getPublicUrl(path);

      if (persistOnProfile) {
        const { error: profErr } = await (supa as any)
          .from("airfnb_profiles")
          .update({ avatar_url: publicUrl })
          .eq("id", userId);
        if (profErr) throw new Error(profErr.message);
      }

      setUrl(publicUrl);
      onUploaded?.(publicUrl);
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
      <button
        type="button"
        onClick={() => fileRef.current?.click()}
        disabled={busy}
        aria-label="Carregar foto de perfil"
        style={{
          width: size, height: size, borderRadius: "50%",
          background: url ? `center/cover no-repeat url(${url})` : "linear-gradient(135deg,#FFE0D2,#FF6133)",
          border: "2px solid var(--line)", cursor: busy ? "wait" : "pointer",
          position: "relative", padding: 0,
        }}
      >
        {!url && <span style={{ position: "absolute", inset: 0, display: "flex", alignItems: "center", justifyContent: "center", color: "#fff", fontFamily: "Bebas Neue, sans-serif", fontSize: size / 3 }}>?</span>}
        {busy && (
          <span style={{
            position: "absolute", inset: 0, borderRadius: "50%",
            background: "rgba(0,0,0,0.5)", color: "#fff",
            display: "flex", alignItems: "center", justifyContent: "center",
            fontSize: 12,
          }}>…</span>
        )}
      </button>
      <input
        ref={fileRef}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        style={{ display: "none" }}
        onChange={(e) => {
          const f = e.target.files?.[0];
          if (f) pickFile(f);
          // clear so re-picking the same file fires onChange again
          if (fileRef.current) fileRef.current.value = "";
        }}
      />
      <div style={{ fontSize: 13, color: "var(--muted)" }}>
        <div style={{ fontWeight: 600, color: "var(--ink)" }}>Foto de perfil</div>
        <div>PNG, JPG ou WebP. Máx {maxMb}MB.</div>
        {err && <div style={{ color: "#8B1100", marginTop: 4 }}>{err}</div>}
      </div>
    </div>
  );
}

/**
 * Compress an image to fit under `maxMb` megabytes by resizing + re-encoding
 * to JPEG. Runs entirely client-side via Canvas. No external dependency.
 */
async function compressTo(file: File, maxMb: number): Promise<Blob> {
  // first try: max dim 1024px, JPEG q=0.85
  let blob = await reencode(file, 1024, 0.85);
  if (blob.size <= maxMb * 1024 * 1024) return blob;
  // second try: 800px, q=0.75
  blob = await reencode(file, 800, 0.75);
  if (blob.size <= maxMb * 1024 * 1024) return blob;
  // last try: 600px, q=0.6
  return reencode(file, 600, 0.6);
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
