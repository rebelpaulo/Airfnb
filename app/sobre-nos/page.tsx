import Link from "next/link";

export default function SobreNosPage() {
  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 760 }}>
      <h1 className="section-title">Sobre nós</h1>
      <p style={{ lineHeight: 1.7, color: "var(--ink)" }}>
        A Air F&amp;B nasceu para encurtar a distância entre quem organiza eventos
        e quem cozinha sobre rodas. Acreditamos que um food truck pode
        transformar qualquer evento — desde um casamento íntimo a um festival
        com milhares de pessoas — desde que a logística não seja uma dor.
      </p>
      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>O que fazemos</h2>
      <p style={{ lineHeight: 1.7 }}>
        Somos um marketplace que liga organizadores a food trucks certificados.
        O organizador publica o evento grátis e recebe propostas em horas;
        o truck candidata-se aos eventos que dão match com o seu calendário.
        Cuidamos da curadoria, da homologação e do pagamento — para que cada
        evento tenha o catering que merece, sem complicações.
      </p>
      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>Valores</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li>Transparência total nos preços e nas regras.</li>
        <li>Curadoria sobre quantidade — só trucks com homologação válida.</li>
        <li>Apoio humano sempre que o automatismo não chega.</li>
      </ul>
      <p style={{ marginTop: 32 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>← Voltar</Link>
      </p>
    </div>
  );
}
