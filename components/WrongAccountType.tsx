import Link from "next/link";

type Props = {
  /** what the user tried to do */
  intent: "add_truck" | "organize_event";
  /** the role they currently have */
  currentRole: "organizer" | "owner";
};

/**
 * Friendly block-page when a user with the wrong account type tries to access
 * a flow reserved for the other side of the marketplace. Roles are exclusive:
 * a single email cannot be both organizer and truck owner — they have to use
 * separate accounts.
 */
export function WrongAccountType({ intent, currentRole }: Props) {
  const isOrg = currentRole === "organizer";
  const title = intent === "add_truck"
    ? "Esta conta é de organizador"
    : "Esta conta é de food truck";
  const lead = intent === "add_truck"
    ? "Para adicionar um food truck precisas de uma conta de operador de truck. As duas funções no marketplace são exclusivas — cada conta serve um lado."
    : "Para organizar um evento precisas de uma conta de organizador. As duas funções no marketplace são exclusivas — cada conta serve um lado.";
  // The `next` param contains its own query string (?as=...), so it must be
  // URL-encoded before being placed inside another query string — otherwise
  // the parser only captures up to the first unencoded `?` and the as= flag
  // silently drops.
  const cta = intent === "add_truck"
    ? { href: `/logout?next=${encodeURIComponent("/signup?as=truck")}`, label: "Sair e criar conta de Food Truck" }
    : { href: `/logout?next=${encodeURIComponent("/signup?as=organizer")}`, label: "Sair e criar conta de Organizador" };
  const back = isOrg
    ? { href: "/dashboard/organizer", label: "← Voltar ao meu painel de organizador" }
    : { href: "/dashboard/truck", label: "← Voltar ao meu painel de truck" };

  return (
    <div className="dash" style={{ maxWidth: 640 }}>
      <div style={{ marginTop: 24, padding: 28, background: "#fff", border: "1px solid var(--line)", borderRadius: 16 }}>
        <div style={{ fontSize: 13, color: "var(--muted)", letterSpacing: 0.4, textTransform: "uppercase", fontWeight: 700 }}>
          Tipo de conta incompatível
        </div>
        <h1 style={{ margin: "6px 0 12px", fontSize: 28 }}>{title}</h1>
        <p style={{ lineHeight: 1.6, color: "var(--ink)" }}>{lead}</p>
        <p style={{ fontSize: 13, color: "var(--muted)", marginTop: 12 }}>
          Razão: a separação evita conflitos de interesse (um truck a publicar
          eventos para si mesmo) e simplifica faturação, avaliações e RGPD.
          Se a tua empresa precisa de ambos os lados, usa dois emails — um
          para cada conta.
        </p>
        <div style={{ display: "flex", gap: 10, marginTop: 20, flexWrap: "wrap" }}>
          <Link href={cta.href as any} className="btn-pill">{cta.label}</Link>
          <Link href={back.href as any} className="btn-pill outline"
                style={{ borderColor: "var(--line)", color: "var(--ink)" }}>
            {back.label}
          </Link>
        </div>
      </div>
    </div>
  );
}
