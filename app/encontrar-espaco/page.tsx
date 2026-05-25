import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Encontrar espaço",
  description: "Encontra o espaço certo para o teu evento — quintas, terraços, jardins e salões compatíveis com food trucks em Portugal.",
  alternates: { canonical: "/encontrar-espaco" },
};

export default function EncontrarEspacoPage() {
  return (
    <div className="container" style={{ paddingTop: 130, paddingBottom: 80, maxWidth: 760 }}>
      <h1 className="section-title">Encontrar espaço</h1>
      <p style={{ color: "var(--muted)", marginTop: -10 }}>
        Quintas, terraços, jardins e salões prontos a receber o teu food truck.
      </p>

      <p style={{ lineHeight: 1.7, marginTop: 22 }}>
        O espaço certo muda tudo: define o ritmo do evento, o tipo de catering
        que faz sentido e a experiência que os convidados vão lembrar. Reunimos
        uma lista curada de espaços em Portugal habituados a receber food trucks
        — com acesso para a viatura, pontos de água e luz, e equipa de apoio
        local.
      </p>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>O que procuramos num espaço</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li>Acesso fácil para um truck de 6 a 12 metros, sem manobras de risco.</li>
        <li>Ponto de água potável e ligação eléctrica a menos de 25 metros.</li>
        <li>Zona de servir com sombra ou cobertura para dias de chuva.</li>
        <li>Casas de banho suficientes para o número de convidados previsto.</li>
        <li>Licenciamento compatível com eventos privados ou corporativos.</li>
      </ul>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>Tipos de espaço</h2>
      <ul style={{ lineHeight: 1.8 }}>
        <li><strong>Quintas e herdades</strong> — ideais para casamentos, baptizados e festas familiares até 250 pessoas.</li>
        <li><strong>Terraços e rooftops urbanos</strong> — perfeitos para lançamentos de marca, afters de conferência e jantares corporativos.</li>
        <li><strong>Jardins privados e parques</strong> — para festas de aniversário, eventos comunitários e mercados de bairro.</li>
        <li><strong>Salões e espaços industriais</strong> — quando o tempo não ajuda e ainda assim queres o ambiente descontraído de um truck.</li>
      </ul>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>Como te ajudamos</h2>
      <p style={{ lineHeight: 1.7 }}>
        Quando publicas o evento no Air F&amp;B, indicas a morada e o tipo de
        espaço. Se ainda não tens espaço fechado, deixa-nos uma nota no wizard
        de publicação — a equipa sugere parceiros disponíveis na zona e data
        que indicaste, sem custo adicional.
      </p>

      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", marginTop: 32 }}>Pronto para avançar?</h2>
      <p style={{ lineHeight: 1.7 }}>
        Publica o evento em 60 segundos e recebe propostas de trucks
        compatíveis com o teu espaço e orçamento.
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
