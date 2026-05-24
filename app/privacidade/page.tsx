import Link from "next/link";

export default function PrivacidadePage() {
  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 760 }}>
      <h1 className="section-title">Privacidade</h1>
      <p style={{ color: "var(--muted)", marginTop: -10 }}>
        Versão resumida das nossas práticas de dados. A política completa será
        publicada antes do lançamento público.
      </p>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 28 }}>O que recolhemos</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li>Nome, email e telemóvel quando crias conta.</li>
        <li>Dados da empresa (nome, NIF) para donos de truck.</li>
        <li>Detalhes dos eventos que publicas ou a que te candidatas.</li>
        <li>Mensagens trocadas entre organizadores e trucks (para suporte).</li>
      </ul>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 28 }}>O que NÃO fazemos</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li>Não vendemos dados a terceiros.</li>
        <li>Não usamos dados sensíveis para perfis publicitários.</li>
        <li>Não enviamos marketing sem opt-in explícito.</li>
      </ul>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 28 }}>Os teus direitos (RGPD)</h2>
      <p style={{ lineHeight: 1.7 }}>
        Podes pedir a qualquer momento exportar ou apagar os teus dados.
        Escreve a <a href="mailto:dpo@airfnb.example" style={{ color: "var(--orange)" }}>dpo@airfnb.example</a>
        {" "}e respondemos em 30 dias.
      </p>

      <p style={{ marginTop: 32 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>← Voltar</Link>
      </p>
    </div>
  );
}
