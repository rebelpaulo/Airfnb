import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Marketing",
  description: "Divulgação, convites e materiais gráficos para eventos com food truck — apoio à comunicação antes, durante e depois do evento.",
  alternates: { canonical: "/marketing" },
};

export default function MarketingPage() {
  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 760 }}>
      <h1 className="section-title">Marketing</h1>
      <p style={{ color: "var(--muted)", marginTop: -10 }}>
        Comunica o teu evento como uma marca — antes, durante e depois.
      </p>

      <p style={{ lineHeight: 1.7, marginTop: 22 }}>
        A diferença entre um evento meio cheio e um evento com fila à entrada
        está quase sempre na comunicação. Ajudamos organizadores e operadores
        de food truck a montar a comunicação certa para cada tipo de evento —
        do convite digital ao relatório pós-evento.
      </p>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>Antes do evento</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li>Convite digital com data, morada, mapa e RSVP.</li>
        <li>Imagem do truck escolhido — para gerar expectativa nos convidados.</li>
        <li>Stories e posts curtos com countdown, em formato vertical.</li>
        <li>Cartaz imprimível em A3 e A4 para eventos abertos ao público.</li>
      </ul>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>Durante o evento</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li>Sinalética de menu no truck, com preços visíveis e legíveis a 3 metros.</li>
        <li>QR code que ligue à página do evento ou ao Instagram do truck.</li>
        <li>Photo spot identificado, para fotos que circulem nas redes.</li>
        <li>Hashtag dedicada, se o evento for público ou de marca.</li>
      </ul>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>Depois do evento</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li>Email de agradecimento aos convidados, com galeria de fotos.</li>
        <li>Relatório curto para sponsors ou direcção, com números do evento.</li>
        <li>Avaliação do truck no Air F&amp;B — ajuda os próximos organizadores.</li>
      </ul>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>Para operadores de truck</h2>
      <p style={{ lineHeight: 1.7 }}>
        Se tens um food truck no Air F&amp;B, divulgamos a tua presença nos
        eventos públicos onde estás escalado: post no Instagram, citação no
        nosso blog e link directo do catálogo. Quanto mais completo for o teu
        perfil (fotos, ementa, certificações), mais visibilidade tens.
      </p>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>Vamos começar?</h2>
      <p style={{ lineHeight: 1.7 }}>
        Publica o evento e a equipa indica que materiais fazem sentido para o
        teu caso — sem custo adicional.
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
