"use client";
import Link from "next/link";
import { useEffect, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

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
  useEffect(() => {
    const on = () => setScrolled(window.scrollY > 60);
    on();
    window.addEventListener("scroll", on, { passive: true });
    return () => window.removeEventListener("scroll", on);
  }, []);

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
        <Link className="logo" href="/">air<span>f.</span>b</Link>
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
    </header>
  );
}
