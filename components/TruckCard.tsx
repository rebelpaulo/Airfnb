"use client";

import Link from "next/link";
import Image from "next/image";
import { useRef, useState } from "react";
import { truckCover } from "@/lib/img";
import { HeartButton } from "@/components/HeartButton";

// Touch-swipe activation threshold. Below 40px the user is probably
// just tapping or scrolling vertically — we don't want stray finger
// drift to flip the photo. 40px is the same value used by the
// react-swipeable defaults for casual horizontal swipes.
const SWIPE_THRESHOLD_PX = 40;

// Card used on /catalogo, /procurar, and anywhere we render a list of
// trucks. Single image was misleading — owners marked food shots as cover,
// so organisers couldn't see what the actual truck looked like. Now:
//
//   - cover_url is the first photo (server-side prefers kind='truck')
//   - gallery_urls is the full ordered list (truck → food → venue → team)
//   - on hover/focus, dots appear under the photo
//   - tapping the dots OR clicking the left/right halves of the image
//     cycles to the next/previous photo without leaving the card
//
// We deliberately don't auto-rotate. Organisers scanning a grid don't want
// the cards moving under their cursor; they pick a truck, then explore.

type Truck = {
  id: string;
  slug: string;
  name: string;
  base_city: string | null;
  cover_url: string | null;
  gallery_urls: string[] | null;
  category_slugs: string[] | null;
  rating_avg: number | string | null;
  rating_count: number | string | null;
};

type Props = {
  truck: Truck;
  initialFavorited: boolean;
  authed: boolean;
  /** Localised "Novo" label for first-rated trucks. */
  newLabel: string;
};

export function TruckCard({ truck, initialFavorited, authed, newLabel }: Props) {
  // De-dupe in case the view returns the cover both standalone and inside
  // the gallery. Falls back to the cover-only list if gallery is empty.
  const gallery = (() => {
    const list = (truck.gallery_urls ?? []).filter(Boolean);
    if (list.length === 0 && truck.cover_url) return [truck.cover_url];
    if (list.length === 0) return [];
    return Array.from(new Set(list)).slice(0, 5);
  })();
  const [idx, setIdx] = useState(0);
  const total = Math.max(1, gallery.length);
  const current = gallery[idx] ?? truck.cover_url ?? null;
  // Track the start of a horizontal touch so we can swipe to next/prev
  // on mobile without the user having to find the dot indicator. We
  // also remember whether the gesture is horizontal — if the user is
  // scrolling vertically we leave touchend alone so the page scrolls
  // normally and we don't fire a stray photo change.
  const touchStartXRef = useRef<number | null>(null);
  const touchStartYRef = useRef<number | null>(null);
  const touchScrollingRef = useRef(false);

  const go = (delta: 1 | -1) => (e: React.MouseEvent) => {
    // Prevent the wrapping <Link> from following the href when the user
    // is just paging through photos.
    e.preventDefault();
    e.stopPropagation();
    setIdx((i) => (i + delta + total) % total);
  };
  const goTo = (i: number) => (e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIdx(i);
  };

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
    // Vertical dominant motion → user is scrolling the page. Mark and
    // skip the swipe handler so we don't steal the gesture.
    if (dy > dx && dy > 12) {
      touchScrollingRef.current = true;
    }
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
    // Prevent the parent Link's onClick from triggering on a tap that
    // happened to end on the image after the swipe completed.
    e.preventDefault();
    setIdx((i) => (i + (dx < 0 ? 1 : -1) + total) % total);
  }

  return (
    <Link href={`/catalogo/${truck.slug}`} className="truck-card">
      <div
        className="thumb"
        style={{ position: "relative", touchAction: "pan-y" }}
        onTouchStart={onTouchStart}
        onTouchMove={onTouchMove}
        onTouchEnd={onTouchEnd}
      >
        <Image
          src={truckCover(current)}
          alt={truck.name}
          fill
          sizes="(max-width: 768px) 100vw, (max-width: 1200px) 33vw, 25vw"
          style={{ objectFit: "cover" }}
        />
        <HeartButton truckId={truck.id} initialFavorited={initialFavorited} authed={authed} />

        {total > 1 && (
          <>
            {/* Click halves — bigger than chevrons, work on touch without
                needing hover. Transparent so they don't intrude visually.
                `top: 56px` leaves the HeartButton's top-right hit area
                free; without that clearance the right pager half stole
                taps on the favourite icon. */}
            <button
              type="button"
              aria-label="Foto anterior"
              onClick={go(-1)}
              style={{
                position: "absolute", left: 0, top: 56, bottom: 0, width: "30%",
                background: "transparent", border: 0, cursor: "pointer", zIndex: 1,
              }}
            />
            <button
              type="button"
              aria-label="Foto seguinte"
              onClick={go(1)}
              style={{
                position: "absolute", right: 0, top: 56, bottom: 0, width: "30%",
                background: "transparent", border: 0, cursor: "pointer", zIndex: 1,
              }}
            />

            {/* Dots indicator (always visible — needed on touch where
                there's no hover signal). The container is presentational
                (no aria-hidden — the dots are focusable buttons, hiding
                them would orphan them from assistive tech). */}
            <div
              role="group"
              aria-label="Galeria de fotos"
              style={{
                position: "absolute", bottom: 8, left: "50%", transform: "translateX(-50%)",
                display: "flex", gap: 6, padding: "4px 8px",
                background: "rgba(0,0,0,0.35)", borderRadius: 999,
                zIndex: 2,
              }}
            >
              {gallery.map((_, i) => (
                <button
                  key={i}
                  type="button"
                  onClick={goTo(i)}
                  aria-label={`Ir para foto ${i + 1} de ${total}`}
                  aria-current={i === idx ? "true" : undefined}
                  style={{
                    width: i === idx ? 8 : 6,
                    height: i === idx ? 8 : 6,
                    borderRadius: "50%",
                    border: 0,
                    background: i === idx ? "#fff" : "rgba(255,255,255,0.55)",
                    padding: 0,
                    cursor: "pointer",
                    transition: "background 0.15s, width 0.15s, height 0.15s",
                  }}
                />
              ))}
            </div>
          </>
        )}
      </div>
      <div className="info">
        <h3>{truck.name}</h3>
        <div className="subtitle">{(truck.category_slugs ?? []).slice(0, 3).join(" · ")}</div>
        <div className="meta">
          <span className="loc">
            <span className="material-symbols-outlined" style={{ fontSize: 18, color: "#FF4919" }}>location_on</span>
            {truck.base_city ?? "—"}
          </span>
          <span className="cap">
            {Number(truck.rating_count) > 0
              ? `★ ${Number(truck.rating_avg).toFixed(1)} (${truck.rating_count})`
              : newLabel}
          </span>
        </div>
      </div>
    </Link>
  );
}
