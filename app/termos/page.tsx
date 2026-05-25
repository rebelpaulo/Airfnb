import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Termos e Condições",
  description: "Termos de utilização do marketplace Air F&B.",
  alternates: { canonical: "/termos" },
};

export default function TermosPage() {
  return (
    <div className="container" style={{ paddingTop: 120, paddingBottom: 80, maxWidth: 780 }}>
      <h1 className="section-title">Termos e Condições</h1>
      <p style={{ color: "var(--muted)", marginTop: -6 }}>
        Última atualização: 25 de maio de 2026.
      </p>

      <Section title="1. Quem somos e o que é a Air F&B">
        A Air F&amp;B (a "plataforma") opera um marketplace que liga organizadores
        de eventos a operadores de food trucks. Não somos parte nos contratos
        entre organizadores e trucks — somos um intermediário tecnológico.
      </Section>

      <Section title="2. Aceitação">
        Ao criar conta aceitas estes termos e a <Link href="/privacidade" style={{ color: "var(--orange)" }}>Política de Privacidade</Link>.
        Se não concordas, não uses o serviço.
      </Section>

      <Section title="3. Conta">
        Tens de ter pelo menos 18 anos. És responsável pela password e por todas
        as ações na tua conta. Devemos ser informados imediatamente em caso de
        suspeita de uso não autorizado.
      </Section>

      <Section title="4. Lock-fee e pagamentos">
        Quando uma candidatura é aceite o truck paga um lock-fee de €50 para
        confirmar a reserva (€25 plataforma + €25 split organizer). Sem
        pagamento dentro do prazo, a candidatura expira e o slot fica
        novamente disponível. Pagamentos processados por Stripe — os dados de
        cartão nunca passam pelos nossos servidores.
      </Section>

      <Section title="5. Conduta">
        Não publicar conteúdo ilegal, ofensivo, ou que viole direitos de terceiros.
        Não tentar contornar o lock-fee combinando fora da plataforma após match.
        Não automatizar candidaturas / pedidos (rate-limits estão activos).
      </Section>

      <Section title="6. Avaliações">
        Avaliações organizer↔truck são publicadas após confirmação do evento.
        Reservamo-nos o direito de remover avaliações com linguagem abusiva,
        difamação ou conteúdo claramente falso.
      </Section>

      <Section title="7. Suspensão e remoção">
        Podemos suspender ou apagar contas que violem estes termos. Podes
        apagar a tua conta a qualquer momento em <Link href="/dashboard/conta" style={{ color: "var(--orange)" }}>A minha conta</Link>.
      </Section>

      <Section title="8. Limitação de responsabilidade">
        A Air F&amp;B não responde pelo cumprimento dos contratos entre
        organizadores e trucks, pela qualidade da comida servida, nem por
        danos resultantes da execução do evento. O nosso limite máximo de
        responsabilidade é, em qualquer caso, o lock-fee aplicável.
      </Section>

      <Section title="9. Lei aplicável">
        Lei portuguesa. Tribunal competente: Comarca de Lisboa.
      </Section>

      <Section title="10. Contacto">
        <a href="mailto:legal@airfnb.pt">legal@airfnb.pt</a>
      </Section>

      <p style={{ marginTop: 40 }}>
        <Link href="/" style={{ color: "var(--orange)" }}>← Voltar</Link>
        &nbsp;·&nbsp;
        <Link href="/privacidade" style={{ color: "var(--orange)" }}>Política de Privacidade →</Link>
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
