import Link from "next/link";
import { getDictionary } from "@/lib/i18n";

export async function Footer() {
  const dict = await getDictionary();
  const t = dict.footer;
  return (
    <footer className="site-footer">
      <div className="newsletter">
        <h2>{t.newsletter_title}</h2>
        <form className="newsletter-form" method="POST" action="/api/newsletter">
          <input type="hidden" name="source" value="footer" />
          <label htmlFor="newsletter-email" style={{ position: "absolute", width: 1, height: 1, padding: 0, margin: -1, overflow: "hidden", clip: "rect(0,0,0,0)", whiteSpace: "nowrap", border: 0 }}>
            {t.email_aria_label}
          </label>
          <input
            id="newsletter-email"
            name="email"
            type="email"
            required
            placeholder={t.email_placeholder}
            aria-label={t.email_aria_label}
          />
          <button type="submit">{t.newsletter_cta}</button>
        </form>
      </div>
      <div className="footer-columns">
        <div>
          <h3>{t.organizers}</h3>
          <ul>
            <li><Link href="/publicar">{t.organizers_publish}</Link></li>
            <li><Link href="/dashboard/organizer">{t.organizers_my_requests}</Link></li>
            <li><Link href="/catalogo">{t.organizers_catalogue}</Link></li>
          </ul>
        </div>
        <div>
          <h3>{t.trucks}</h3>
          <ul>
            <li><Link href="/pedidos">{t.trucks_open_requests}</Link></li>
            <li><Link href="/dashboard/truck">{t.trucks_my_applications}</Link></li>
            <li><Link href="/signup?as=truck">{t.trucks_add_truck}</Link></li>
          </ul>
        </div>
        <div>
          <h3>{t.about}</h3>
          <ul>
            <li><Link href="/sobre-nos">{t.about_about_us}</Link></li>
            <li><Link href="/equipa">{t.about_team}</Link></li>
            <li><Link href="/blog">{t.about_blog}</Link></li>
            <li><Link href="/ajuda">{t.about_help}</Link></li>
            <li><Link href="/privacidade">{t.about_privacy}</Link></li>
          </ul>
        </div>
      </div>
      <p className="copyright">{t.copyright}</p>
    </footer>
  );
}
