import Link from "next/link";

export function Footer() {
  return (
    <footer className="site-footer">
      <div className="newsletter">
        <h2>Receba todas as novidades do mercado</h2>
        <form className="newsletter-form">
          <label htmlFor="newsletter-email" style={{ position: "absolute", width: 1, height: 1, padding: 0, margin: -1, overflow: "hidden", clip: "rect(0,0,0,0)", whiteSpace: "nowrap", border: 0 }}>
            Email para subscrever a newsletter
          </label>
          <input
            id="newsletter-email"
            name="email"
            type="email"
            required
            placeholder="Insira o seu email"
            aria-label="Email para subscrever a newsletter"
          />
          <button type="submit">SUBSCREVER</button>
        </form>
      </div>
      <div className="footer-columns">
        <div>
          <h3>Organizers</h3>
          <ul>
            <li><Link href="/publicar">Publicar pedido</Link></li>
            <li><Link href="/dashboard/organizer">Os meus pedidos</Link></li>
            <li><Link href="/catalogo">Inspira-te no catálogo</Link></li>
          </ul>
        </div>
        <div>
          <h3>Trucks</h3>
          <ul>
            <li><Link href="/pedidos">Pedidos abertos</Link></li>
            <li><Link href="/dashboard/truck">As minhas candidaturas</Link></li>
            <li><Link href="/signup?as=truck">Adicionar truck</Link></li>
          </ul>
        </div>
        <div>
          <h3>Air F&amp;B</h3>
          <ul>
            <li><Link href="/sobre-nos">Sobre Nós</Link></li>
            <li><Link href="/equipa">Equipa</Link></li>
            <li><Link href="/blog">Blog</Link></li>
            <li><Link href="/ajuda">Ajuda</Link></li>
            <li><Link href="/privacidade">Privacidade</Link></li>
          </ul>
        </div>
      </div>
      <p className="copyright">© 2024 Air F&amp;B. Todos os direitos reservados.</p>
    </footer>
  );
}
