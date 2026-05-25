"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

type Role = "organizer" | "owner" | "admin" | null;
type Dict = Record<string, string>;

// `exact` forces equality on the route match; without it a sub-route like
// /dashboard/organizer/eventos would mark BOTH the parent /dashboard/organizer
// item AND the child item as active. Use it on the role landing page.
type Item = { href: string; icon: string; key: keyof typeof LABEL_KEYS; exact?: boolean };

const LABEL_KEYS = {
  // shared
  favorites:     "nav_favorites",
  conversations: "nav_conversations",
  notifications: "nav_notifications",
  account:       "nav_account",
  profile:       "nav_profile",
  invite:        "nav_invite",
  // organizer
  org_dashboard: "nav_organizer_dashboard",
  org_events:    "nav_organizer_events",
  org_publish:   "nav_organizer_publish",
  // owner
  owner_dashboard:    "nav_owner_dashboard",
  owner_opportunities:"nav_owner_opportunities",
  owner_applications: "nav_owner_applications",
  // admin
  admin_dashboard: "nav_admin_dashboard",
  admin_trucks:    "nav_admin_trucks",
  admin_settings:  "nav_admin_settings",
} as const;

/**
 * Build the sidebar item list for the active role. Shared items go first,
 * then role-specific sections.
 */
function itemsForRole(role: Role): { section: string; items: Item[] }[] {
  const shared: Item[] = [
    { href: "/dashboard/favoritos",     icon: "favorite",      key: "favorites" },
    { href: "/dashboard/conversas",     icon: "chat_bubble",   key: "conversations" },
    { href: "/dashboard/notificacoes",  icon: "notifications", key: "notifications" },
    { href: "/dashboard/perfil",        icon: "person",        key: "profile" },
    { href: "/dashboard/conta",         icon: "settings",      key: "account" },
    { href: "/dashboard/convidar",      icon: "card_giftcard", key: "invite" },
  ];

  if (role === "owner") {
    return [
      { section: "trucks", items: [
        { href: "/dashboard/truck",                icon: "local_shipping", key: "owner_dashboard", exact: true },
        { href: "/dashboard/truck/oportunidades",  icon: "explore",        key: "owner_opportunities" },
        { href: "/dashboard/truck/aplicacoes",     icon: "assignment",     key: "owner_applications" },
      ]},
      { section: "shared", items: shared },
    ];
  }
  if (role === "organizer") {
    return [
      { section: "events", items: [
        { href: "/dashboard/organizer",         icon: "list_alt",    key: "org_dashboard", exact: true },
        { href: "/dashboard/organizer/eventos", icon: "event",       key: "org_events" },
        { href: "/publicar",                    icon: "add_circle",  key: "org_publish" },
      ]},
      { section: "shared", items: shared },
    ];
  }
  if (role === "admin") {
    return [
      { section: "admin", items: [
        { href: "/admin",            icon: "admin_panel_settings", key: "admin_dashboard" },
        { href: "/admin/trucks",     icon: "fact_check",           key: "admin_trucks" },
        { href: "/admin/definicoes", icon: "tune",                 key: "admin_settings" },
      ]},
      { section: "shared", items: shared },
    ];
  }
  // No role yet — show only the shared items + a hint to set up.
  return [{ section: "shared", items: shared }];
}

export function DashboardSidebar({ role, name, dict }: { role: Role; name: string; dict: Dict }) {
  const pathname = usePathname();
  const groups = itemsForRole(role);

  return (
    <aside style={{
      borderRight: "1px solid var(--line)",
      background: "#FAFAFA",
      padding: "24px 16px",
      position: "sticky", top: 72, height: "calc(100dvh - 72px)",
      overflowY: "auto",
    }}>
      <div style={{ padding: "0 8px 16px", borderBottom: "1px solid var(--line)", marginBottom: 16 }}>
        <div style={{ fontSize: 12, color: "var(--muted)", letterSpacing: 0.4, textTransform: "uppercase", fontWeight: 700 }}>
          {dict.signed_in_as}
        </div>
        <div style={{ fontWeight: 700, marginTop: 4, wordBreak: "break-word" }}>{name}</div>
        {role && (
          <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 4, textTransform: "capitalize" }}>
            {dict[`role_${role}`] ?? role}
          </div>
        )}
      </div>

      {groups.map((g, gi) => (
        <ul key={g.section} style={{ listStyle: "none", padding: 0, margin: 0, marginTop: gi === 0 ? 0 : 20 }}>
          {gi > 0 && (
            <li style={{ padding: "0 8px 8px", fontSize: 11, color: "var(--muted)", letterSpacing: 0.4, textTransform: "uppercase", fontWeight: 700 }}>
              {dict[`section_${g.section}`] ?? g.section}
            </li>
          )}
          {g.items.map((item) => {
            const active = item.exact
              ? pathname === item.href
              : pathname === item.href || pathname.startsWith(item.href + "/");
            return (
              <li key={item.href}>
                <Link href={item.href} style={{
                  display: "flex", alignItems: "center", gap: 12,
                  padding: "10px 12px",
                  borderRadius: 8,
                  color: active ? "#fff" : "var(--ink)",
                  background: active ? "var(--orange)" : "transparent",
                  fontWeight: active ? 700 : 500,
                  fontSize: 14,
                  marginBottom: 2,
                  transition: "background 0.12s, color 0.12s",
                }}>
                  <span className="material-symbols-outlined" style={{ fontSize: 20 }} aria-hidden="true">
                    {item.icon}
                  </span>
                  {dict[LABEL_KEYS[item.key]] ?? item.key}
                </Link>
              </li>
            );
          })}
        </ul>
      ))}
    </aside>
  );
}
