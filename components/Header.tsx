"use client";
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { Logo } from "@/components/Logo";

type Props = {
  user: {
    id: string;
    email: string;
    role: string | null;
    avatarUrl?: string | null;
    displayName?: string | null;
  } | null;
};

export function Header({ user }: Props) {
  const [scrolled, setScrolled] = useState(false);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [servicesOpen, setServicesOpen] = useState(false);
  const drawerRef = useRef<HTMLElement | null>(null);
  const menuButtonRef = useRef<HTMLButtonElement | null>(null);
  useEffect(() => {
    const on = () => setScrolled(window.scrollY > 60);
    on();
    window.addEventListener("scroll", on, { passive: true });
    return () => window.removeEventListener("scroll", on);
  }, []);
  // Drawer A11y: lock body scroll, close on Escape, trap Tab inside the drawer,
  // and restore focus to the trigger when closing — required behavior for
  // role="dialog" aria-modal="true" per ARIA APG.
  useEffect(() => {
    if (!drawerOpen) return;
    const opener = document.activeElement as HTMLElement | null;
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    // Move focus to the first focusable element inside the drawer on open
    requestAnimationFrame(() => {
      const first = drawerRef.current?.querySelector<HTMLElement>(
        'a, button, [tabindex]:not([tabindex="-1"])',
      );
      first?.focus();
    });

    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        setDrawerOpen(false);
        return;
      }
      if (e.key !== "Tab" || !drawerRef.current) return;
      const focusables = Array.from(
        drawerRef.current.querySelectorAll<HTMLElement>(
          'a, button:not([disabled]), [tabindex]:not([tabindex="-1"])',
        ),
      ).filter((el) => el.offsetParent !== null);
      if (focusables.length === 0) return;
      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      if (e.shiftKey && document.activeElement === first) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = prevOverflow;
      window.removeEventListener("keydown", onKey);
      // Restore focus to whoever opened the drawer (the menu button by default)
      (opener ?? menuButtonRef.current)?.focus();
    };
  }, [drawerOpen]);

  // Be explicit: unknown / null roles route to the organizer dashboard (the
  // safer default — organizer dashboard is read-only by default and won't
  // expose owner-only flows).
  const dashboardHref = user?.role === "owner"
    ? "/dashboard/truck"
    : user?.role === "organizer" || user?.role === "admin" || user?.role === "staff"
      ? "/dashboard/organizer"
      : "/dashboard/organizer";

  // supabaseBrowser() reads env at call time and throws if NEXT_PUBLIC_*
  // is missing. Do NOT call it at render — defer to the actual handler so
  // SSR/SSG won't crash on misconfigured deployments. The handler runs only
  // when the user clicks logout, by which point env should be present.
  const signOut = async () => {
    const supa = supabaseBrowser();
    const { error } = await supa.auth.signOut();
    if (error) {
      alert(`Erro ao terminar sessão: ${error.message}`);
      return;
    }
    window.location.href = "/";
  };
  const initial = (user?.displayName || user?.email || "?")[0]?.toUpperCase();

  return (
    <header className={`site-header ${scrolled ? "scrolled" : ""}`}>
      <div className="brand">
        <button
          ref={menuButtonRef}
          type="button"
          className="menu-btn"
          aria-label="Abrir menu"
          aria-expanded={drawerOpen}
          onClick={() => setDrawerOpen(true)}
        >
          <span className="material-symbols-outlined">menu</span>
        </button>
        <Link className="logo" href="/" aria-label="Air F&amp;B">
          <Logo variant="white" height={36} />
        </Link>
      </div>
      <ul className="main-nav">
        <li><Link href="/catalogo">Encontrar Trucks</Link></li>
        <li><Link href="/publicar">Organizar evento</Link></li>
        <li><Link href="/blog">Blog</Link></li>
        <li><Link href="/registar">Adicionar Truck</Link></li>
      </ul>
      <div className="header-actions">
        {user ? (
          <>
            <Link className="icon-chip" href="/dashboard/notificacoes" aria-label="Notificações">
              <span className="material-symbols-outlined">notifications</span>
            </Link>
            <Link
              className="icon-chip"
              href={dashboardHref}
              title={user.displayName ?? user.email}
              aria-label={`Dashboard de ${user.displayName ?? user.email}`}
              style={{ display: "inline-flex", alignItems: "center", gap: 8 }}
            >
              {user.avatarUrl ? (
                <span
                  aria-hidden="true"
                  style={{
                    display: "inline-block", width: 28, height: 28, borderRadius: "50%",
                    background: `center/cover no-repeat url(${user.avatarUrl})`,
                    border: "1.5px solid rgba(255,255,255,0.7)",
                  }}
                />
              ) : (
                <span
                  aria-hidden="true"
                  style={{
                    display: "inline-flex", alignItems: "center", justifyContent: "center",
                    width: 28, height: 28, borderRadius: "50%",
                    background: "rgba(255,255,255,0.18)", color: "#fff",
                    fontFamily: "Bebas Neue, sans-serif", fontSize: 14, letterSpacing: 0,
                  }}
                >
                  {initial}
                </span>
              )}
              <span className="label-hide">Dashboard</span>
            </Link>
            <button
              className="icon-chip"
              aria-label="Terminar sessão"
              onClick={signOut}
            >
              <span className="material-symbols-outlined">logout</span>
            </button>
          </>
        ) : (
          <>
            <Link className="icon-chip" href="/login">
              <span className="material-symbols-outlined">login</span>
              <span className="label-hide">Entrar</span>
            </Link>
            <Link className="icon-chip" href="/signup">
              <span className="material-symbols-outlined">person_add</span>
              <span className="label-hide">Registar</span>
            </Link>
          </>
        )}
      </div>

      {drawerOpen && (
        <>
          <div
            onClick={() => setDrawerOpen(false)}
            style={{
              position: "fixed", inset: 0, background: "rgba(0,0,0,0.4)",
              zIndex: 40,
            }}
            aria-hidden="true"
          />
          <aside
            ref={drawerRef}
            role="dialog"
            aria-modal="true"
            aria-label="Menu de navegação"
            style={{
              position: "fixed", top: 0, left: 0, bottom: 0,
              width: "min(360px, 88vw)", background: "#fff", color: "var(--ink)",
              zIndex: 50, boxShadow: "0 0 40px rgba(0,0,0,0.25)",
              padding: "22px 26px", overflowY: "auto",
              fontFamily: "Montserrat, system-ui, sans-serif",
            }}
          >
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 18 }}>
              <Logo variant="black" height={28} />
              <button
                type="button"
                onClick={() => setDrawerOpen(false)}
                aria-label="Fechar menu"
                style={{ background: "transparent", border: "none", cursor: "pointer", fontSize: 22, color: "var(--muted)", padding: 4 }}
              >×</button>
            </div>

            <ul style={{ listStyle: "none", padding: 0, margin: 0, display: "grid", gap: 4 }}>
              {user && (
                <DrawerLink href={dashboardHref} onClose={() => setDrawerOpen(false)}>Perfil</DrawerLink>
              )}
              <DrawerLink href="/publicar"  onClose={() => setDrawerOpen(false)}>Organizar Evento</DrawerLink>
              <DrawerLink href="/catalogo"  onClose={() => setDrawerOpen(false)}>Encontrar Trucks</DrawerLink>
              <DrawerLink href="/registar"  onClose={() => setDrawerOpen(false)}>Adicionar Truck</DrawerLink>

              <li>
                <button
                  type="button"
                  onClick={() => setServicesOpen((s) => !s)}
                  aria-expanded={servicesOpen}
                  style={{
                    width: "100%", display: "flex", justifyContent: "space-between", alignItems: "center",
                    background: "transparent", border: "none", cursor: "pointer", padding: "12px 0",
                    fontFamily: "inherit", fontSize: 16, fontWeight: 600, color: "var(--ink)",
                  }}
                >
                  Serviços
                  <span aria-hidden="true" style={{ color: "var(--muted)", fontSize: 18 }}>
                    {servicesOpen ? "−" : "+"}
                  </span>
                </button>
                {servicesOpen && (
                  <ul style={{ listStyle: "none", padding: 0, margin: "0 0 0 14px", display: "grid", gap: 2, color: "var(--muted)" }}>
                    <DrawerLink href="/encontrar-espaco"  onClose={() => setDrawerOpen(false)} small>Espaços p/ Eventos</DrawerLink>
                    <DrawerLink href="/gestao-convidados" onClose={() => setDrawerOpen(false)} small>Gestão de Convidados</DrawerLink>
                    <DrawerLink href="/musica-animacao"   onClose={() => setDrawerOpen(false)} small>Música & Animação</DrawerLink>
                    <DrawerLink href="/marketing"         onClose={() => setDrawerOpen(false)} small>Marketing & Publicidade</DrawerLink>
                  </ul>
                )}
              </li>

              <DrawerLink href="/blog"        onClose={() => setDrawerOpen(false)}>Blog</DrawerLink>
              <DrawerLink href="/privacidade" onClose={() => setDrawerOpen(false)}>Termos e Condições</DrawerLink>
              <DrawerLink href="/ajuda"       onClose={() => setDrawerOpen(false)}>Precisa de Ajuda?</DrawerLink>
            </ul>

            {user && (
              <div style={{ marginTop: 22, paddingTop: 18, borderTop: "1px solid var(--line)" }}>
                <button
                  type="button"
                  onClick={() => { setDrawerOpen(false); signOut(); }}
                  style={{
                    background: "transparent", border: "none", cursor: "pointer", padding: 0,
                    fontFamily: "inherit", fontSize: 15, fontWeight: 600, color: "var(--orange)",
                  }}
                >
                  Terminar sessão
                </button>
              </div>
            )}
          </aside>
        </>
      )}
    </header>
  );
}

function DrawerLink({ href, children, onClose, small }: { href: string; children: React.ReactNode; onClose: () => void; small?: boolean }) {
  return (
    <li>
      <Link
        href={href as any}
        onClick={onClose}
        style={{
          display: "block", padding: small ? "8px 0" : "12px 0",
          color: small ? "var(--muted)" : "var(--ink)",
          fontSize: small ? 14 : 16, fontWeight: small ? 500 : 600,
          textDecoration: "none",
        }}
      >
        {children}
      </Link>
    </li>
  );
}
