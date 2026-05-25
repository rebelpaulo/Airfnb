import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Música e animação",
  description: "DJs, bandas ao vivo e animação para complementar o teu food truck — sugestões de parceiros e dicas práticas.",
  alternates: { canonical: "/musica-animacao" },
};

export default function MusicaAnimacaoPage() {
  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 760 }}>
      <h1 className="section-title">Música e animação</h1>
      <p style={{ color: "var(--muted)", marginTop: -10 }}>
        O som certo transforma o teu evento — escolhe-o com a mesma curadoria
        que escolhes o catering.
      </p>

      <p style={{ lineHeight: 1.7, marginTop: 22 }}>
        Um food truck cria um ambiente descontraído, quase de mercado nocturno.
        A música e a animação que escolheres devem acompanhar esse tom: nem
        formal de mais, nem caótico ao ponto de tapar a conversa. Aqui
        partilhamos o que funciona para diferentes tipos de evento.
      </p>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>Para cada tipo de evento</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li><strong>Casamentos</strong> — banda acústica durante o serviço, DJ para a pista a partir das 23h.</li>
        <li><strong>Eventos corporativos</strong> — playlist curada com volume controlado durante o networking, opcional DJ no after.</li>
        <li><strong>Aniversários e festas privadas</strong> — DJ residente ou playlist colaborativa em Spotify; karaoke costuma resultar bem.</li>
        <li><strong>Lançamentos e activações de marca</strong> — DJ com identidade alinhada à marca, eventual performance ao vivo de 30 minutos.</li>
        <li><strong>Festivais e mercados</strong> — alinhamento de várias bandas em palco partilhado, com pausas para chamada aos trucks.</li>
      </ul>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>Logística que costuma falhar</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li>Som a competir com o motor do truck — separa as zonas ou desliga o gerador durante a actuação.</li>
        <li>Falta de pontos de corrente independentes para PA e cozinha.</li>
        <li>Horário de início mal combinado com o pico do serviço — coordena com o truck.</li>
        <li>Licença SPA / passagem de obra em eventos públicos esquecida na produção.</li>
      </ul>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>Parceiros</h2>
      <p style={{ lineHeight: 1.7 }}>
        Estamos a construir uma rede de DJs, bandas e animadores recomendados
        — com perfis verificados e disponibilidade visível. Para já, quando
        publicas o evento podes deixar nota a indicar que procuras sugestão
        de animação. A equipa responde em 48 horas com 2 a 3 contactos
        compatíveis.
      </p>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>Pronto a montar o ambiente?</h2>
      <p style={{ lineHeight: 1.7 }}>
        Começa por publicar o evento com o truck. A animação encaixa depois,
        com mais clareza sobre horário e número de convidados.
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
