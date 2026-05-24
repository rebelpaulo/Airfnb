"use client";
import { useState } from "react";

type Props = {
  name: string;
  label: string;
  defaultValue?: number;
  required?: boolean;
};

/**
 * Hidden input that posts the value, with 5 clickable star buttons.
 * Plain CSS for the filled/empty state so this works in server-rendered
 * forms without extra deps.
 */
export function StarRating({ name, label, defaultValue = 0, required = false }: Props) {
  const [value, setValue] = useState(defaultValue);
  const [hover, setHover] = useState(0);
  const display = hover || value;

  return (
    <div style={{ display: "grid", gap: 6 }}>
      <label style={{ fontSize: 13, fontWeight: 600, color: "var(--ink)" }}>
        {label} {required && <span style={{ color: "var(--orange)" }}>*</span>}
      </label>
      <div style={{ display: "flex", gap: 4 }} onMouseLeave={() => setHover(0)}>
        {[1, 2, 3, 4, 5].map((n) => (
          <button
            key={n}
            type="button"
            aria-label={`${n} ${n === 1 ? "estrela" : "estrelas"}`}
            onClick={() => setValue(n)}
            onMouseEnter={() => setHover(n)}
            style={{
              background: "transparent", border: "none", cursor: "pointer", padding: 4,
              fontSize: 30, lineHeight: 1, color: n <= display ? "#FFB300" : "#D9D9D9",
              transition: "color .12s, transform .12s",
              transform: n === hover ? "scale(1.1)" : "none",
            }}
          >
            ★
          </button>
        ))}
        <span style={{ alignSelf: "center", marginLeft: 8, fontSize: 13, color: "var(--muted)" }}>
          {value > 0 ? `${value}/5` : "Sem rating"}
        </span>
      </div>
      <input type="hidden" name={name} value={value || ""} required={required} />
    </div>
  );
}
