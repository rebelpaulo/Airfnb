import Link from "next/link";

export default function EquipaPage() {
  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 760 }}>
      <h1 className="section-title">Equipa</h1>
      <p style={{ color: "var(--muted)", marginTop: -10 }}>
        Somos uma equipa pequena baseada em Lisboa, com experiência em
        marketplaces, eventos e restauração.
      </p>
      <p style={{ lineHeight: 1.7, marginTop: 24 }}>
        Em vez de uma página institucional, preferimos estar disponíveis.
        Manda-nos uma mensagem em <Link href="/ajuda" style={{ color: "var(--orange)" }}>Ajuda</Link>
        {" "}e respondemos em horas úteis. Para parcerias, escreve directamente a
        {" "}<a href="mailto:hello@airfnb.example" style={{ color: "var(--orange)" }}>hello@airfnb.example</a>.
      </p>
      <p style={{ marginTop: 32 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>← Voltar</Link>
      </p>
    </div>
  );
}
