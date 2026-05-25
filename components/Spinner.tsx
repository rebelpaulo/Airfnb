/**
 * Inline spinner — pure CSS, respects prefers-reduced-motion via the
 * shared `airfnb-spin` keyframe in globals.css. Use inside text labels (e.g.
 * server-action pending state) or as a fallback when a button doesn't
 * have `.busy` toggled.
 *
 * Example:
 *   <button disabled={busy}>{busy ? <Spinner label="A enviar…" /> : "Enviar"}</button>
 *
 * For the more common `<button className={`btn-pill ${busy ? "busy" : ""}`}>` pattern,
 * just toggle the `busy` class — the spinner replaces the label automatically.
 */
type Props = {
  /** Optional text shown next to the spinner. */
  label?: string;
  /** Pixel size (defaults to 14 — sits well inside body text / buttons). */
  size?: number;
  /** Hex color of the rotating arc; defaults to currentColor so it inherits. */
  color?: string;
};

export function Spinner({ label, size = 14, color }: Props) {
  return (
    <span
      role="status"
      aria-live="polite"
      style={{ display: "inline-flex", alignItems: "center", gap: 8 }}
    >
      <span
        aria-hidden="true"
        style={{
          display: "inline-block",
          width: size,
          height: size,
          border: `2px solid ${color ?? "currentColor"}`,
          borderTopColor: "transparent",
          borderRadius: "50%",
          animation: "airfnb-spin 0.7s linear infinite",
          opacity: 0.85,
        }}
      />
      {label && <span>{label}</span>}
    </span>
  );
}
