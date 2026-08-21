import Link from "next/link";

export default function NotFound() {
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
          404
        </div>
        <h1 style={{ margin: "6px 0 12px", fontSize: 28 }}>
          Esta página não existe
        </h1>
        <p style={{ lineHeight: 1.6, color: "var(--ink)" }}>
          O link pode estar partido ou a página pode ter sido movida. Verifica
          o endereço ou volta à página inicial para continuar.
        </p>
        <div style={{ display: "flex", gap: 10, marginTop: 20, flexWrap: "wrap" }}>
          <Link href="/" className="btn-pill">Voltar ao início</Link>
          <Link href="/catalogo" className="btn-pill outline"
                style={{ borderColor: "var(--line)", color: "var(--ink)" }}>
            Ver catálogo
          </Link>
        </div>
      </div>
    </div>
  );
}
