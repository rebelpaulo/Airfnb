"use client";
import { useEffect, useId, useRef, useState } from "react";

type Suggestion = {
  display_name: string;
  lat: string;
  lon: string;
  address?: { city?: string; town?: string; village?: string; municipality?: string; country?: string; country_code?: string };
};

type Props = {
  name?: string;             // form field name
  defaultValue?: string;
  placeholder?: string;
  required?: boolean;
  /** called when the user picks a suggestion (or clears) */
  onChange?: (city: string, full?: Suggestion) => void;
  /** restrict to a single country code (ISO 3166-1 alpha-2). Default 'pt'. */
  country?: string;
  /** dropdown stays inside an overflow:hidden parent when this is true */
  inline?: boolean;
  style?: React.CSSProperties;
  className?: string;
};

/**
 * Free city autocomplete backed by OpenStreetMap's Nominatim API.
 * - No API key, fair-use rate limit (1 req/sec). We debounce 300ms.
 * - Returns the human-readable city/town/village, never a street.
 * - Easy to swap for Google Places later: replace the fetch URL in
 *   `lookup()` and the result mapping in `pickName()` — the component
 *   interface stays the same.
 */
export function CityAutocomplete({
  name = "city",
  defaultValue = "",
  placeholder = "Cidade ou localidade",
  required = false,
  onChange,
  country = "pt",
  inline = false,
  style,
  className,
}: Props) {
  const id = useId();
  const [query, setQuery]     = useState(defaultValue);
  const [items, setItems]     = useState<Suggestion[]>([]);
  const [open, setOpen]       = useState(false);
  const [activeIx, setActive] = useState(-1);
  const boxRef = useRef<HTMLDivElement | null>(null);
  const lastReq = useRef(0);

  // Debounced fetch to respect Nominatim's fair-use policy (1 req/sec)
  useEffect(() => {
    const term = query.trim();
    if (term.length < 2) { setItems([]); return; }
    const t = setTimeout(() => lookup(term), 300);
    return () => clearTimeout(t);
  }, [query, country]);

  // Close dropdown on outside click
  useEffect(() => {
    if (!open) return;
    const onDoc = (e: MouseEvent) => {
      if (boxRef.current && !boxRef.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", onDoc);
    return () => document.removeEventListener("mousedown", onDoc);
  }, [open]);

  async function lookup(term: string) {
    const myReq = ++lastReq.current;
    try {
      const url = new URL("https://nominatim.openstreetmap.org/search");
      url.searchParams.set("q", term);
      url.searchParams.set("format", "json");
      url.searchParams.set("addressdetails", "1");
      url.searchParams.set("limit", "6");
      url.searchParams.set("featuretype", "settlement");  // prefer towns/cities
      if (country) url.searchParams.set("countrycodes", country);
      const r = await fetch(url.toString(), {
        // Nominatim requires a descriptive UA; the browser sends its own
        // which is acceptable. Still set Accept-Language for PT-friendly names.
        headers: { "accept-language": "pt-PT,pt;q=0.9,en;q=0.8" },
      });
      if (!r.ok) return;
      const data = (await r.json()) as Suggestion[];
      // Drop stale responses if the user kept typing
      if (myReq !== lastReq.current) return;
      // Filter to settlement-like results (place name matches city/town/village)
      const filtered = data.filter((d) => {
        const a = d.address ?? {};
        return a.city || a.town || a.village || a.municipality;
      });
      setItems(filtered);
      setOpen(filtered.length > 0);
      setActive(-1);
    } catch {
      /* offline, network error → silently empty */
    }
  }

  function pickName(s: Suggestion): string {
    const a = s.address ?? {};
    return a.city ?? a.town ?? a.village ?? a.municipality ?? s.display_name.split(",")[0];
  }

  function choose(s: Suggestion) {
    const name = pickName(s);
    setQuery(name);
    setItems([]);
    setOpen(false);
    onChange?.(name, s);
  }

  function onKey(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setOpen(true);
      setActive((i) => Math.min(items.length - 1, i + 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((i) => Math.max(0, i - 1));
    } else if (e.key === "Enter") {
      if (activeIx >= 0 && items[activeIx]) {
        e.preventDefault();
        choose(items[activeIx]);
      }
    } else if (e.key === "Escape") {
      setOpen(false);
    }
  }

  return (
    <div ref={boxRef} style={{ position: "relative", ...style }} className={className}>
      <input
        id={id}
        name={name}
        type="text"
        autoComplete="off"
        required={required}
        value={query}
        placeholder={placeholder}
        onChange={(e) => { setQuery(e.target.value); onChange?.(e.target.value); }}
        onFocus={() => items.length > 0 && setOpen(true)}
        onKeyDown={onKey}
        role="combobox"
        aria-expanded={open}
        aria-controls={`${id}-listbox`}
        aria-autocomplete="list"
        aria-activedescendant={activeIx >= 0 ? `${id}-opt-${activeIx}` : undefined}
      />
      {open && items.length > 0 && (
        <ul
          id={`${id}-listbox`}
          role="listbox"
          style={{
            position: inline ? "relative" : "absolute",
            top: inline ? undefined : "calc(100% + 4px)",
            left: 0,
            right: 0,
            zIndex: 50,
            background: "#fff",
            border: "1px solid var(--line)",
            borderRadius: 10,
            boxShadow: "0 12px 32px rgba(0,0,0,0.12)",
            listStyle: "none",
            margin: 0,
            padding: 4,
            maxHeight: 260,
            overflowY: "auto",
            color: "var(--ink)",
          }}
        >
          {items.map((s, i) => {
            const a = s.address ?? {};
            const primary = pickName(s);
            const sub = [a.municipality && a.municipality !== primary ? a.municipality : null, a.country].filter(Boolean).join(", ");
            return (
              <li
                key={`${s.lat}-${s.lon}`}
                id={`${id}-opt-${i}`}
                role="option"
                aria-selected={i === activeIx}
                onMouseEnter={() => setActive(i)}
                onMouseDown={(e) => { e.preventDefault(); choose(s); }}
                style={{
                  padding: "10px 12px",
                  borderRadius: 8,
                  cursor: "pointer",
                  background: i === activeIx ? "#FFF6F2" : "transparent",
                  display: "grid", gap: 2,
                }}
              >
                <strong style={{ fontSize: 14 }}>{primary}</strong>
                {sub && <span style={{ fontSize: 12, color: "var(--muted)" }}>{sub}</span>}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
