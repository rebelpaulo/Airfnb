"use client";

import Link from "next/link";
import { useEffect } from "react";

export default function ErrorPage({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => {
    // Log to console so it shows up in Vercel runtime logs / browser devtools.
    console.error("App error boundary caught:", error);
  }, [error]);

  return (
    <div className="dash" style={{ maxWidth: 640 }}>
      <div style={{
        marginTop: 24, padding: 28, background: "#fff",
        border: "1px solid var(--line)", borderRadius: 16,
      }}>
        <div style={{
          fontSize: 13, color: "var(--muted)", letterSpacing: 0.4,
          textTransform: "uppercase", fontWeight: 700,
        }}>
          Erro inesperado
        </div>
        <h1 style={{ margin: "6px 0 12px", fontSize: 28 }}>
          Algo correu mal
        </h1>
        <p style={{ lineHeight: 1.6, color: "var(--ink)" }}>
          Não conseguimos carregar esta página. Podes tentar novamente — se o
          erro persistir, escreve-nos pelo formulário de ajuda.
        </p>
        {error.digest && (
          <p style={{ fontSize: 12, color: "var(--muted)", marginTop: 10, fontFamily: "monospace" }}>
            Ref: {error.digest}
          </p>
        )}
        <div style={{ display: "flex", gap: 10, marginTop: 20, flexWrap: "wrap" }}>
          <button type="button" onClick={reset} className="btn-pill">
            Tentar novamente
          </button>
          <Link href="/" className="btn-pill outline"
                style={{ borderColor: "var(--line)", color: "var(--ink)" }}>
            Voltar ao início
          </Link>
        </div>
      </div>
    </div>
  );
}
