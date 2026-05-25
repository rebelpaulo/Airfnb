// Inline form submitting to /api/locale — no client JS required, works
// for users with JS off. The selected language is highlighted by the
// parent passing `current`.
import type { Locale } from "@/lib/i18n";

export function LangToggle({ current }: { current: Locale }) {
  return (
    <form
      method="POST"
      action="/api/locale"
      style={{ display: "inline-flex", gap: 2, alignItems: "center", marginLeft: 6 }}
      aria-label="Idioma"
    >
      <button
        type="submit" name="lang" value="pt"
        aria-pressed={current === "pt"}
        title="Português"
        style={btn(current === "pt")}
      >PT</button>
      <span style={{ color: "rgba(255,255,255,0.4)", fontSize: 11 }}>|</span>
      <button
        type="submit" name="lang" value="en"
        aria-pressed={current === "en"}
        title="English"
        style={btn(current === "en")}
      >EN</button>
    </form>
  );
}

function btn(active: boolean): React.CSSProperties {
  return {
    background: "transparent",
    border: "none",
    color: active ? "#fff" : "rgba(255,255,255,0.55)",
    fontSize: 12,
    fontWeight: active ? 700 : 500,
    padding: "4px 6px",
    cursor: "pointer",
    fontFamily: "inherit",
    letterSpacing: 0.5,
  };
}
