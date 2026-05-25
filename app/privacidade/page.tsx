import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Política de Privacidade",
  description: "Como a Air F&B trata os teus dados pessoais sob o RGPD.",
  alternates: { canonical: "/privacidade" },
};

export default function PrivacidadePage() {
  return (
    <div className="container" style={{ paddingTop: 120, paddingBottom: 80, maxWidth: 780 }}>
      <h1 className="section-title">Política de Privacidade</h1>
      <p style={{ color: "var(--muted)", marginTop: -6 }}>
        Última atualização: 25 de maio de 2026.
      </p>

      <Section title="Quem somos">
        Air F&amp;B opera o marketplace de food trucks em <strong>airfnb.vercel.app</strong>.
        Para questões de privacidade escreve para <a href="mailto:privacidade@airfnb.pt">privacidade@airfnb.pt</a>.
      </Section>

      <Section title="Dados que recolhemos">
        <ul>
          <li><strong>Conta</strong>: email, nome, password (hash), papel (organizer / owner), idioma.</li>
          <li><strong>Perfil</strong>: empresa, NIF, telefone, avatar, cidade base.</li>
          <li><strong>Conteúdo do marketplace</strong>: trucks que publicas, pedidos de evento que crias, candidaturas, mensagens nas conversas, avaliações.</li>
          <li><strong>Pagamentos</strong>: registo dos lock-fees pagos (montante, referência Stripe). Os dados do cartão ficam no Stripe — nunca chegam aos nossos servidores.</li>
          <li><strong>Técnicos</strong>: IP truncado, user-agent, timestamps de pedidos a APIs.</li>
        </ul>
      </Section>

      <Section title="Para que usamos">
        <ul>
          <li><strong>Operar o serviço</strong>: matching organizer↔truck, cobrança do lock-fee, notificações.</li>
          <li><strong>Confiança</strong>: avaliações e dossiês de homologação públicas.</li>
          <li><strong>Segurança</strong>: prevenção de fraude e rate-limiting.</li>
          <li><strong>Comunicação</strong>: emails transacionais (candidatura aceite, pagamento, etc.); newsletter só se subscreveres.</li>
        </ul>
      </Section>

      <Section title="Bases legais (Art. 6 RGPD)">
        <ul>
          <li>Execução do contrato — para gerir candidaturas, bookings, pagamentos.</li>
          <li>Interesse legítimo — para anti-spam, segurança e melhorias.</li>
          <li>Consentimento — para a newsletter.</li>
          <li>Obrigação legal — para faturação e retenção fiscal.</li>
        </ul>
      </Section>

      <Section title="Partilha com terceiros">
        <ul>
          <li><strong>Stripe</strong> (pagamentos)</li>
          <li><strong>Supabase</strong> (hosting da base de dados, na UE)</li>
          <li><strong>Vercel</strong> (hosting da aplicação)</li>
          <li>Não vendemos dados a terceiros.</li>
        </ul>
      </Section>

      <Section title="Retenção">
        <ul>
          <li>Conta ativa — enquanto manténs a conta.</li>
          <li>Faturação — 10 anos (obrigação fiscal portuguesa).</li>
          <li>Logs técnicos — 90 dias.</li>
          <li>Newsletter — até cancelares.</li>
        </ul>
      </Section>

      <Section title="Os teus direitos (Art. 15-22 RGPD)">
        <ul>
          <li><strong>Acesso</strong>: pedir uma cópia integral dos teus dados — basta usar o botão em <Link href="/dashboard/conta">A minha conta</Link>.</li>
          <li><strong>Retificação</strong>: editar perfil / trucks no dashboard.</li>
          <li><strong>Apagamento</strong>: apagar a conta e tudo o que está ligada a ela em <Link href="/dashboard/conta">A minha conta</Link> (excepto registos fiscais que somos obrigados a guardar).</li>
          <li><strong>Portabilidade</strong>: o export está em JSON aberto.</li>
          <li><strong>Reclamação</strong>: à CNPD em <a href="https://www.cnpd.pt" target="_blank" rel="noopener noreferrer">cnpd.pt</a>.</li>
        </ul>
      </Section>

      <Section title="Cookies">
        Usamos apenas cookies estritamente necessários (sessão Supabase). Sem cookies de tracking
        de terceiros nem analytics na primeira release.
      </Section>

      <Section title="Alterações">
        Atualizações materiais a esta política são comunicadas por email com 14 dias de antecedência.
      </Section>

      <p style={{ marginTop: 40 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>← Voltar</Link>
        &nbsp;·&nbsp;
        <Link href="/termos" style={{ color: "var(--orange)" }}>Termos e Condições →</Link>
      </p>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section style={{ marginTop: 28 }}>
      <h2 style={{ fontFamily: "Bebas Neue, sans-serif", color: "var(--teal)", fontSize: 24, margin: "0 0 8px" }}>
        {title}
      </h2>
      <div style={{ lineHeight: 1.65, color: "var(--ink)" }}>{children}</div>
    </section>
  );
}
