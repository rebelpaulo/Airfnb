"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

export type DashboardRole = "organizer" | "owner" | "admin" | "staff" | null;
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
function itemsForRole(role: DashboardRole): { section: string; items: Item[] }[] {
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
  if (role === "admin" || role === "staff") {
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

function DashboardIdentity({ role, name, dict }: { role: DashboardRole; name: string; dict: Dict }) {
  return (
    <div className="dashboard-sidebar__identity">
      <div className="dashboard-sidebar__eyebrow">{dict.signed_in_as}</div>
      <div className="dashboard-sidebar__name">{name}</div>
      {role ? (
        <div className="dashboard-sidebar__role">
          {dict[`role_${role}`] ?? role}
        </div>
      ) : null}
    </div>
  );
}

function DashboardNavigation({
  groups,
  pathname,
  dict,
  label,
}: {
  groups: ReturnType<typeof itemsForRole>;
  pathname: string;
  dict: Dict;
  label: string;
}) {
  return (
    <nav aria-label={label}>
      {groups.map((group, groupIndex) => (
        <ul
          className="dashboard-sidebar__group"
          data-subsequent={groupIndex > 0 ? "true" : undefined}
          key={group.section}
        >
          {groupIndex > 0 ? (
            <li className="dashboard-sidebar__section">
              {dict[`section_${group.section}`] ?? group.section}
            </li>
          ) : null}
          {group.items.map((item) => {
            const active = item.exact
              ? pathname === item.href
              : pathname === item.href || pathname.startsWith(item.href + "/");

            return (
              <li key={item.href}>
                <Link
                  aria-current={active ? "page" : undefined}
                  className="dashboard-sidebar__link"
                  data-active={active ? "true" : undefined}
                  href={item.href}
                >
                  <span className="material-symbols-outlined dashboard-sidebar__icon" aria-hidden="true">
                    {item.icon}
                  </span>
                  <span>{dict[LABEL_KEYS[item.key]] ?? item.key}</span>
                </Link>
              </li>
            );
          })}
        </ul>
      ))}
    </nav>
  );
}

export function DashboardSidebar({ role, name, dict }: { role: DashboardRole; name: string; dict: Dict }) {
  const pathname = usePathname();
  const groups = itemsForRole(role);
  const roleLabel = role ? (dict[`role_${role}`] ?? role) : dict.section_shared;

  return (
    <aside className="dashboard-sidebar">
      <div className="dashboard-sidebar__desktop">
        <DashboardIdentity role={role} name={name} dict={dict} />
        <DashboardNavigation groups={groups} pathname={pathname} dict={dict} label="Dashboard" />
      </div>

      <details className="dashboard-sidebar__mobile">
        <summary className="dashboard-sidebar__summary">
          <span className="dashboard-sidebar__summary-copy">
            <span className="dashboard-sidebar__summary-name">{name}</span>
            <span className="dashboard-sidebar__summary-role">{roleLabel}</span>
          </span>
          <span className="dashboard-sidebar__summary-action">
            <span className="material-symbols-outlined" aria-hidden="true">menu</span>
            <span>Menu</span>
          </span>
        </summary>
        <div className="dashboard-sidebar__mobile-panel">
          <DashboardNavigation groups={groups} pathname={pathname} dict={dict} label="Dashboard" />
        </div>
      </details>
    </aside>
  );
}
