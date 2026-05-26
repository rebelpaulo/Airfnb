"use client";

import Image from "next/image";
import { useState } from "react";

// Big-image + thumbnails strip used on /catalogo/[slug]. Click a thumb to
// promote it to the hero, or use prev/next on the hero itself. Designed
// to be reachable by keyboard (chevrons are <button>s; thumbs are too).
//
// We keep the server-rendered ordering — parent passes `images` in the
// already-sorted list (truck → food → venue → team). The active index
// state lives only in the client.

type Img = { id: string; url: string; alt?: string | null };

type Props = {
  images: Img[];
  /** Used as the alt when an image has no explicit alt of its own. */
  fallbackAlt: string;
};

export function TruckGallery({ images, fallbackAlt }: Props) {
  const [idx, setIdx] = useState(0);
  if (images.length === 0) return null;

  const total = images.length;
  const active = images[idx];

  const go = (delta: 1 | -1) => () => {
    setIdx((i) => (i + delta + total) % total);
  };

  return (
    <div>
      <div
        className="thumb"
        style={{ aspectRatio: "16/10", position: "relative" }}
      >
        <Image
          src={active.url}
          alt={active.alt ?? fallbackAlt}
          fill
          sizes="(max-width: 768px) 100vw, 66vw"
          priority
          style={{ objectFit: "cover" }}
        />

        {total > 1 && (
          <>
            <button
              type="button"
              onClick={go(-1)}
              aria-label="Foto anterior"
              style={chevronStyle("left")}
            >
              <span className="material-symbols-outlined" aria-hidden="true">chevron_left</span>
            </button>
            <button
              type="button"
              onClick={go(1)}
              aria-label="Foto seguinte"
              style={chevronStyle("right")}
            >
              <span className="material-symbols-outlined" aria-hidden="true">chevron_right</span>
            </button>

            {/* Counter chip top-right — gives a quick sense of how much
                more is in the gallery beyond the visible thumb strip. */}
            <div
              style={{
                position: "absolute", top: 12, right: 12,
                padding: "4px 10px", fontSize: 12, fontWeight: 600,
                background: "rgba(0,0,0,0.55)", color: "#fff",
                borderRadius: 999,
              }}
              aria-hidden="true"
            >
              {idx + 1} / {total}
            </div>
          </>
        )}
      </div>

      {total > 1 && (
        <div
          role="tablist"
          aria-label="Galeria de fotos"
          style={{
            display: "grid",
            gridTemplateColumns: `repeat(${Math.min(total, 5)}, 1fr)`,
            gap: 8, marginTop: 8,
          }}
        >
          {images.slice(0, 5).map((img, i) => (
            <button
              key={img.id}
              type="button"
              role="tab"
              aria-selected={i === idx}
              onClick={() => setIdx(i)}
              className="thumb"
              style={{
                aspectRatio: "1/1", position: "relative",
                padding: 0, border: 0, background: "transparent",
                outline: i === idx ? "2px solid var(--orange)" : "2px solid transparent",
                outlineOffset: 2,
                borderRadius: 8,
                overflow: "hidden",
                cursor: "pointer",
              }}
            >
              <Image
                src={img.url}
                alt={img.alt ?? ""}
                fill
                sizes="(max-width: 768px) 25vw, 165px"
                style={{ objectFit: "cover", opacity: i === idx ? 1 : 0.85, transition: "opacity 0.15s" }}
              />
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function chevronStyle(side: "left" | "right"): React.CSSProperties {
  return {
    position: "absolute",
    [side]: 12,
    top: "50%",
    transform: "translateY(-50%)",
    width: 40, height: 40,
    borderRadius: "50%",
    border: 0,
    background: "rgba(0,0,0,0.55)",
    color: "#fff",
    cursor: "pointer",
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    zIndex: 2,
  };
}
