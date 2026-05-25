import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Gestão de convidados",
  description: "Convites, RSVP, lista de presenças e contagem por refeição — organiza o teu evento com food truck sem dores de cabeça.",
  alternates: { canonical: "/gestao-convidados" },
};

export default function GestaoConvidadosPage() {
  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 760 }}>
      <h1 className="section-title">Gestão de convidados</h1>
      <p style={{ color: "var(--muted)", marginTop: -10 }}>
        Convites, RSVP e contagem de refeições — tudo coordenado com o truck.
      </p>

      <p style={{ lineHeight: 1.7, marginTop: 22 }}>
        Saber quantos convidados vão aparecer, o que comem e a que horas
        chegam é o que separa um evento descontraído de uma noite caótica para
        a equipa do truck. Ajudamos-te a passar esta informação ao operador no
        formato certo — sem folhas de Excel infinitas nem mensagens perdidas.
      </p>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>O que pedimos no wizard</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li>Número esperado de convidados (com margem mínima e máxima).</li>
        <li>Horário de chegada e janela de serviço prevista.</li>
        <li>Restrições alimentares conhecidas — vegetarianos, vegan, sem glúten, alergias.</li>
        <li>Se há crianças e se precisas de opções dedicadas.</li>
      </ul>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>RSVP e contagens finais</h2>
      <p style={{ lineHeight: 1.7 }}>
        Os trucks parceiros ajustam a produção em função do número final que
        confirmares até 72 horas antes do evento. Pequenas variações (até 10%)
        são absorvidas sem custo; ajustes maiores são acertados na conversa do
        evento, antes do dia.
      </p>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>Comunicação durante o evento</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li>Contacto directo do responsável do truck partilhado na confirmação.</li>
        <li>Conversa no dashboard com histórico de tudo o que foi combinado.</li>
        <li>Avisos de chegada e estado do serviço em tempo real.</li>
      </ul>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>Boas práticas</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li>Avisa os convidados que o catering é em truck — gera expectativa correcta.</li>
        <li>Indica horários por blocos quando o evento for grande, para evitar filas.</li>
        <li>Reserva espaço de mesas próximo do truck para quem prefere comer sentado.</li>
      </ul>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>Começa o teu evento</h2>
      <p style={{ lineHeight: 1.7 }}>
        Publica o evento, indica o número de convidados e recebe propostas de
        trucks com capacidade real para o servir.
      </p>
      <p style={{ marginTop: 18 }}>
        <Link href="/publicar" className="btn-pill">Organizar evento</Link>
      </p>

      <p style={{ marginTop: 32 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>← Voltar</Link>
      </p>
    </div>
  );
}
