"use client";

import Image from "next/image";
import { useCallback, useEffect, useRef, useState } from "react";

// Big-image + thumbnails strip used on /catalogo/[slug]. Click the hero
// or any thumb to open a full-screen lightbox modal with chevrons, a
// counter, keyboard arrows, esc-to-close, click-outside-to-close, focus
// trap and mobile swipe gestures.
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

// Same threshold the card carousel uses for swipe-to-page so the
// gesture feels consistent across the app.
const SWIPE_THRESHOLD_PX = 40;

export function TruckGallery({ images, fallbackAlt }: Props) {
  const [idx, setIdx] = useState(0);
  const [lightboxOpen, setLightboxOpen] = useState(false);
  if (images.length === 0) return null;

  const total = images.length;
  // Clamp the index in case `images` shrinks via parent re-render
  // (e.g. owner deletes a photo). Without this `images[idx]` becomes
  // undefined and the first <Image src={...}> dereference crashes.
  const safeIdx = Math.min(idx, total - 1);
  const active = images[safeIdx];

  const go = (delta: 1 | -1) => () => {
    setIdx((i) => (i + delta + total) % total);
  };
  const openLightboxAt = (i: number) => () => {
    setIdx(i);
    setLightboxOpen(true);
  };

  return (
    <div>
      <button
        type="button"
        onClick={openLightboxAt(safeIdx)}
        aria-label={(active.alt && active.alt.trim())
          ? `${active.alt} — abrir em grande`
          : `Abrir foto ${safeIdx + 1} de ${total} em grande`}
        className="thumb"
        style={{
          aspectRatio: "16/10", position: "relative",
          padding: 0, border: 0, background: "transparent",
          width: "100%", cursor: "zoom-in",
          borderRadius: 14, overflow: "hidden",
        }}
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
            {/* Hero chevrons live on top of the click-to-open button
                using stopPropagation so users can page without
                triggering the lightbox until they're ready. */}
            <span
              role="button"
              tabIndex={0}
              onClick={(e) => { e.preventDefault(); e.stopPropagation(); go(-1)(); }}
              onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); e.stopPropagation(); go(-1)(); } }}
              aria-label="Foto anterior"
              style={chevronStyle("left")}
            >
              <span className="material-symbols-outlined" aria-hidden="true">chevron_left</span>
            </span>
            <span
              role="button"
              tabIndex={0}
              onClick={(e) => { e.preventDefault(); e.stopPropagation(); go(1)(); }}
              onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); e.stopPropagation(); go(1)(); } }}
              aria-label="Foto seguinte"
              style={chevronStyle("right")}
            >
              <span className="material-symbols-outlined" aria-hidden="true">chevron_right</span>
            </span>

            {/* Counter chip top-right — gives a quick sense of how much
                more is in the gallery beyond the visible thumb strip. */}
            <span
              style={{
                position: "absolute", top: 12, right: 12,
                padding: "4px 10px", fontSize: 12, fontWeight: 600,
                background: "rgba(0,0,0,0.55)", color: "#fff",
                borderRadius: 999,
              }}
              aria-hidden="true"
            >
              {safeIdx + 1} / {total}
            </span>
          </>
        )}
      </button>

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
              aria-selected={i === safeIdx}
              aria-label={img.alt && img.alt.trim() ? img.alt : `Ver foto ${i + 1} de ${total}`}
              onClick={openLightboxAt(i)}
              className="thumb"
              style={{
                aspectRatio: "1/1", position: "relative",
                padding: 0, border: 0, background: "transparent",
                outline: i === safeIdx ? "2px solid var(--orange)" : "2px solid transparent",
                outlineOffset: 2,
                borderRadius: 8,
                overflow: "hidden",
                cursor: "zoom-in",
              }}
            >
              <Image
                src={img.url}
                alt={img.alt ?? ""}
                fill
                sizes="(max-width: 768px) 25vw, 165px"
                style={{ objectFit: "cover", opacity: i === safeIdx ? 1 : 0.85, transition: "opacity 0.15s" }}
              />
            </button>
          ))}
        </div>
      )}

      {lightboxOpen && (
        <Lightbox
          images={images}
          startIdx={safeIdx}
          fallbackAlt={fallbackAlt}
          onClose={() => setLightboxOpen(false)}
          onIndexChange={setIdx}
        />
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

// =====================================================================
// Lightbox — full-screen overlay with keyboard nav, swipe and a focus
// trap. Renders inline (not via portal) because Next.js client comps
// can return JSX freely and the fixed positioning takes it out of the
// document flow anyway.
// =====================================================================

function Lightbox({
  images, startIdx, fallbackAlt, onClose, onIndexChange,
}: {
  images: Img[];
  startIdx: number;
  fallbackAlt: string;
  onClose: () => void;
  onIndexChange: (i: number) => void;
}) {
  const [idx, setIdx] = useState(startIdx);
  const total = images.length;
  const safeIdx = Math.min(idx, total - 1);
  const active = images[safeIdx];

  const closeBtnRef = useRef<HTMLButtonElement | null>(null);
  const overlayRef  = useRef<HTMLDivElement | null>(null);
  const touchStartXRef = useRef<number | null>(null);
  const touchStartYRef = useRef<number | null>(null);
  const touchScrollingRef = useRef(false);

  const close = useCallback(() => {
    onIndexChange(safeIdx);
    onClose();
  }, [onClose, onIndexChange, safeIdx]);

  const go = useCallback((delta: 1 | -1) => {
    setIdx((i) => (i + delta + total) % total);
  }, [total]);

  // Lock body scroll, listen for Esc + arrow keys, restore focus on
  // close. Required ARIA modal behavior.
  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    // Move focus into the dialog on open so screen readers and Tab
    // navigation start inside the modal.
    requestAnimationFrame(() => closeBtnRef.current?.focus());

    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape")       { e.preventDefault(); close(); return; }
      if (e.key === "ArrowLeft")    { e.preventDefault(); go(-1); return; }
      if (e.key === "ArrowRight")   { e.preventDefault(); go(1);  return; }
      if (e.key === "Tab") {
        // Two focusable buttons in the dialog (close + chevrons appear
        // when total>1). Cycle Tab between them.
        const focusables = overlayRef.current?.querySelectorAll<HTMLElement>(
          'button:not([disabled]), [tabindex]:not([tabindex="-1"])',
        );
        if (!focusables || focusables.length === 0) return;
        const first = focusables[0];
        const last  = focusables[focusables.length - 1];
        if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
        else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
      }
    };
    window.addEventListener("keydown", onKey);

    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = prevOverflow;
      // Restore focus to whatever opened the dialog.
      opener?.focus();
    };
  }, [close, go]);

  function onTouchStart(e: React.TouchEvent) {
    if (total <= 1) return;
    const t = e.touches[0];
    touchStartXRef.current = t.clientX;
    touchStartYRef.current = t.clientY;
    touchScrollingRef.current = false;
  }
  function onTouchMove(e: React.TouchEvent) {
    if (touchStartXRef.current === null || touchStartYRef.current === null) return;
    const t = e.touches[0];
    const dx = Math.abs(t.clientX - touchStartXRef.current);
    const dy = Math.abs(t.clientY - touchStartYRef.current);
    if (dy > dx && dy > 12) touchScrollingRef.current = true;
  }
  function onTouchEnd(e: React.TouchEvent) {
    if (touchStartXRef.current === null) return;
    if (touchScrollingRef.current) {
      touchStartXRef.current = null;
      touchStartYRef.current = null;
      return;
    }
    const endX = e.changedTouches[0]?.clientX ?? touchStartXRef.current;
    const dx = endX - touchStartXRef.current;
    touchStartXRef.current = null;
    touchStartYRef.current = null;
    if (Math.abs(dx) < SWIPE_THRESHOLD_PX) return;
    go(dx < 0 ? 1 : -1);
  }

  return (
    <div
      ref={overlayRef}
      role="dialog"
      aria-modal="true"
      aria-label={`Galeria de fotos — ${safeIdx + 1} de ${total}`}
      // Click on the overlay (but not on the inner image / controls)
      // closes the dialog. Stop propagation on the inner content keeps
      // the click-to-close working as expected.
      onClick={(e) => { if (e.target === overlayRef.current) close(); }}
      onTouchStart={onTouchStart}
      onTouchMove={onTouchMove}
      onTouchEnd={onTouchEnd}
      style={{
        position: "fixed", inset: 0, zIndex: 1000,
        background: "rgba(0,0,0,0.92)",
        display: "flex", alignItems: "center", justifyContent: "center",
        padding: "min(5vw, 64px)",
        touchAction: "pan-y",
      }}
    >
      {/* Close button — top-right, always reachable even with one photo. */}
      <button
        ref={closeBtnRef}
        type="button"
        onClick={close}
        aria-label="Fechar galeria"
        style={{
          position: "absolute", top: 18, right: 18,
          width: 44, height: 44, borderRadius: "50%",
          border: 0, background: "rgba(255,255,255,0.12)", color: "#fff",
          cursor: "pointer",
          display: "inline-flex", alignItems: "center", justifyContent: "center",
          fontSize: 24,
        }}
      >
        <span className="material-symbols-outlined" aria-hidden="true">close</span>
      </button>

      {/* The image — wrapped in a non-clickable container so click-outside
          on the overlay reliably hits the overlayRef, not the image. */}
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          position: "relative", width: "100%", height: "100%",
          maxWidth: 1400, maxHeight: "100%",
        }}
      >
        <Image
          src={active.url}
          alt={active.alt ?? fallbackAlt}
          fill
          sizes="100vw"
          priority
          style={{ objectFit: "contain" }}
        />
      </div>

      {total > 1 && (
        <>
          <button
            type="button"
            onClick={(e) => { e.stopPropagation(); go(-1); }}
            aria-label="Foto anterior"
            style={lightboxChevronStyle("left")}
          >
            <span className="material-symbols-outlined" aria-hidden="true">chevron_left</span>
          </button>
          <button
            type="button"
            onClick={(e) => { e.stopPropagation(); go(1); }}
            aria-label="Foto seguinte"
            style={lightboxChevronStyle("right")}
          >
            <span className="material-symbols-outlined" aria-hidden="true">chevron_right</span>
          </button>

          {/* Counter pill bottom-centre. */}
          <div
            style={{
              position: "absolute", bottom: 18, left: "50%", transform: "translateX(-50%)",
              padding: "6px 14px",
              background: "rgba(255,255,255,0.12)", color: "#fff",
              borderRadius: 999, fontSize: 13, fontWeight: 600,
            }}
            aria-live="polite"
          >
            {safeIdx + 1} / {total}
          </div>
        </>
      )}
    </div>
  );
}

function lightboxChevronStyle(side: "left" | "right"): React.CSSProperties {
  return {
    position: "absolute",
    [side]: "max(2vw, 18px)",
    top: "50%",
    transform: "translateY(-50%)",
    width: 52, height: 52,
    borderRadius: "50%",
    border: 0,
    background: "rgba(255,255,255,0.14)",
    color: "#fff",
    cursor: "pointer",
    display: "inline-flex",
    alignItems: "center",
    justifyContent: "center",
    fontSize: 28,
    zIndex: 2,
  };
}
