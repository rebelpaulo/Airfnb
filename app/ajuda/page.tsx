import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Ajuda",
  description:
    "Tira dúvidas sobre publicar eventos, registar trucks ou receber propostas — a equipa Air F&B responde em horas úteis.",
  alternates: { canonical: "/ajuda" },
};

export default function AjudaPage() {
  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 760 }}>
      <h1 className="section-title">Ajuda</h1>
      <p style={{ color: "var(--muted)", marginTop: -10 }}>
        Estamos aqui para destravar o teu evento (ou a tua candidatura) o mais
        rápido possível.
      </p>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 28 }}>Sou organizador</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li>O <Link href="/publicar" style={{ color: "var(--orange)" }}>wizard de publicação</Link> leva 60 segundos.</li>
        <li>Recebes as propostas no <Link href="/dashboard/organizer" style={{ color: "var(--orange)" }}>teu dashboard</Link>.</li>
        <li>Publicar é grátis — a plataforma só cobra ao truck quando é aceite.</li>
      </ul>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 28 }}>Tenho um food truck</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li>Começa em <Link href="/registar" style={{ color: "var(--orange)" }}>Registar Food Truck</Link>.</li>
        <li>Podes ter vários trucks na mesma empresa — cada um com o seu calendário e candidaturas.</li>
        <li>Cada truck passa por revisão da equipa antes de ficar visível no catálogo.</li>
      </ul>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 28 }}>Falar com a equipa</h2>
      <p style={{ lineHeight: 1.7 }}>
        Email: <a href="mailto:ola@airfnb.example" style={{ color: "var(--orange)" }}>ola@airfnb.example</a>
        <br />WhatsApp: brevemente
      </p>

      <p style={{ marginTop: 32 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>← Voltar</Link>
      </p>
    </div>
  );
}
