"use client";
import { useState } from "react";

export function CopyButton({ text }: { text: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      type="button"
      className="btn-pill"
      style={{ padding: "10px 22px" }}
      onClick={async () => {
        try {
          await navigator.clipboard.writeText(text);
          setCopied(true);
          setTimeout(() => setCopied(false), 1500);
        } catch {
          // Fallback for browsers without clipboard API (e.g., http preview)
          window.prompt("Copia o link:", text);
        }
      }}
    >
      {copied ? "Copiado ✓" : "Copiar"}
    </button>
  );
}
