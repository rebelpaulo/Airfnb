"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useDict } from "@/components/DictProvider";

// Single avatar-chip dropdown for the authenticated header. Replaces the
// previous cluster of 4 icons (NotifBell + chat link + avatar+dashboard
// link + logout button) with one trigger that opens a menu containing
// every action that used to live in the bar.
//
// Notification count: a small red dot on the chip when there's anything
// unread, so the at-a-glance signal survives the collapse. Exact count
// shown next to "Notificações" inside the menu. Realtime subscription
// (the bit that used to live in NotifBell) was moved here so the
// component owns its data and the dropdown can render unread state
// inline.

type User = {
  id: string;
  email: string;
  role: string | null;
  avatarUrl?: string | null;
  displayName?: string | null;
};

type Props = {
  user: User;
  dashboardHref: string;
};

export function AccountMenu({ user, dashboardHref }: Props) {
  const dict = useDict();
  const t = dict.header;
  const tBell = dict.dashboard.shared_notification_bell;
  const [open, setOpen] = useState(false);
  const [unread, setUnread] = useState(0);
  const wrapperRef = useRef<HTMLDivElement | null>(null);
  const triggerRef = useRef<HTMLButtonElement | null>(null);

  const initial = (user.displayName || user.email || "?")[0]?.toUpperCase();

  // Realtime unread count — initial fetch + INSERT bumps + UPDATE on
  // read_at to keep cross-tab in sync. Mirrors the old NotifBell logic.
  useEffect(() => {
    let cancelled = false;
    const supa = supabaseBrowser();
    (async () => {
      const { count } = await (supa as any)
        .from("airfnb_notifications")
        .select("id", { count: "exact", head: true })
        .eq("user_id", user.id)
        .is("read_at", null);
      if (!cancelled) setUnread(count ?? 0);
    })();
    const ch = supa
      .channel(`notif:${user.id}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "airfnb_notifications", filter: `user_id=eq.${user.id}` },
        () => setUnread((n) => n + 1),
      )
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "airfnb_notifications", filter: `user_id=eq.${user.id}` },
        (p) => {
          const oldRead = (p.old as any)?.read_at;
          const newRead = (p.new as any)?.read_at;
          if (!oldRead && newRead) setUnread((n) => Math.max(0, n - 1));
        },
      )
      .subscribe();
    return () => {
      cancelled = true;
      supa.removeChannel(ch).catch(() => undefined);
    };
  }, [user.id]);

  // Click-outside + Esc dismiss the dropdown. Focus returns to the
  // trigger on close so keyboard users don't lose their place.
  useEffect(() => {
    if (!open) return;
    const onDocClick = (e: MouseEvent) => {
      if (!wrapperRef.current?.contains(e.target as Node)) {
        setOpen(false);
        // Mirror the Esc handler — restore focus to the trigger so keyboard
        // users (and screen-reader users who closed via outside click) don't
        // lose their place in the tab order.
        triggerRef.current?.focus();
      }
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setOpen(false);
        triggerRef.current?.focus();
      }
    };
    document.addEventListener("mousedown", onDocClick);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDocClick);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  async function onSignOut() {
    const supa = supabaseBrowser();
    const { error } = await supa.auth.signOut();
    if (error) {
      alert(`${t.logout_error_prefix} ${error.message}`);
      return;
    }
    window.location.href = "/";
  }

  return (
    <div ref={wrapperRef} style={{ position: "relative" }}>
      <button
        ref={triggerRef}
        type="button"
        className="icon-chip"
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="menu"
        aria-expanded={open}
        // Announce the trigger's purpose ("opens the account menu") while
        // still surfacing the user identity — screen-reader users hear
        // "Conta — Paulo" instead of just "Paulo" with no hint that the
        // button opens a menu.
        aria-label={`${t.account_menu_aria ?? "Conta"} — ${user.displayName ?? user.email}`}
        style={{ display: "inline-flex", alignItems: "center", gap: 8, position: "relative" }}
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
              fontFamily: "Bebas Neue, sans-serif", fontSize: 14,
            }}
          >
            {initial}
          </span>
        )}
        {/* Red dot — at-a-glance unread signal that survives the
            avatar-chip collapse. Exact count lives next to
            "Notificações" inside the menu. */}
        {unread > 0 && (
          <span
            aria-hidden="true"
            style={{
              position: "absolute", top: 2, right: 2,
              width: 10, height: 10, borderRadius: "50%",
              background: "#FF4919", border: "1.5px solid var(--orange-hero)",
            }}
          />
        )}
      </button>

      {open && (
        <div
          role="menu"
          aria-label={t.account_menu_aria ?? "Conta"}
          style={{
            position: "absolute", top: "calc(100% + 8px)", right: 0,
            minWidth: 240,
            background: "#fff", color: "var(--ink)",
            border: "1px solid var(--line)", borderRadius: 12,
            boxShadow: "0 10px 32px rgba(0,0,0,0.18)",
            padding: 6, zIndex: 50,
          }}
        >
          <div style={{ padding: "8px 12px 10px", borderBottom: "1px solid var(--line)", marginBottom: 6 }}>
            <div style={{ fontWeight: 700, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
              {user.displayName ?? user.email}
            </div>
            {user.displayName && (
              <div style={{ fontSize: 12, color: "var(--muted)", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                {user.email}
              </div>
            )}
          </div>
          <MenuLink href={dashboardHref} icon="dashboard" label={t.dashboard_label} onClose={() => setOpen(false)} />
          <MenuLink
            href="/dashboard/notificacoes"
            icon="notifications"
            label={t.menu_notifications ?? "Notificações"}
            badge={unread > 0 ? (unread > 99 ? "99+" : String(unread)) : null}
            onClose={() => setOpen(false)}
          />
          <MenuLink href="/dashboard/conversas" icon="chat_bubble" label={t.menu_conversations ?? "Conversas"} onClose={() => setOpen(false)} />
          <MenuLink href="/dashboard/perfil" icon="person" label={t.menu_profile ?? "Perfil"} onClose={() => setOpen(false)} />
          <div style={{ height: 1, background: "var(--line)", margin: "6px 0" }} />
          <button
            type="button"
            role="menuitem"
            onClick={onSignOut}
            style={{
              ...menuItemBase,
              color: "var(--ink)",
              background: "transparent",
              border: 0,
              cursor: "pointer",
              fontFamily: "inherit",
              fontSize: 14,
              width: "100%", textAlign: "left",
            }}
          >
            <span className="material-symbols-outlined" aria-hidden="true" style={{ fontSize: 18, color: "var(--muted)" }}>logout</span>
            {t.menu_logout ?? t.logout_aria}
          </button>
        </div>
      )}

      {tBell ? <span style={{ display: "none" }}>{tBell.aria_unread_suffix}</span> : null}
    </div>
  );
}

function MenuLink({ href, icon, label, badge, onClose }: {
  href: string; icon: string; label: string; badge?: string | null; onClose: () => void;
}) {
  return (
    <Link
      href={href}
      role="menuitem"
      onClick={onClose}
      style={{ ...menuItemBase }}
    >
      <span className="material-symbols-outlined" aria-hidden="true" style={{ fontSize: 18, color: "var(--muted)" }}>{icon}</span>
      <span style={{ flex: 1 }}>{label}</span>
      {badge && (
        <span style={{
          background: "#FF4919", color: "#fff", fontSize: 11, fontWeight: 700,
          minWidth: 18, height: 18, borderRadius: 999,
          display: "inline-flex", alignItems: "center", justifyContent: "center",
          padding: "0 6px",
        }}>{badge}</span>
      )}
    </Link>
  );
}

const menuItemBase: React.CSSProperties = {
  display: "flex", alignItems: "center", gap: 10,
  padding: "10px 12px", borderRadius: 8,
  color: "var(--ink)", textDecoration: "none",
  fontSize: 14, fontWeight: 500,
  transition: "background 0.12s",
};
