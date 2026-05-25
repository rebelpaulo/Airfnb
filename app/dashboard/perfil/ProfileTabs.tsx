"use client";

import { useRef, useState, type ReactNode } from "react";
import { useDict } from "@/components/DictProvider";

type TabKey = "personal" | "billing";

type Props = {
  /** Personal tab body (form). */
  personal: ReactNode;
  /** Billing tab body (form). */
  billing: ReactNode;
  /** Which tab to open initially — handy when redirecting back after save. */
  initial?: TabKey;
};

/**
 * Tab switcher for /dashboard/perfil. Each tab is a separate <form> with
 * its own server action so saving one tab doesn't blank the other.
 *
 * Implements the WAI-ARIA Tabs pattern with manual activation:
 *   - tab.aria-controls ↔ tabpanel.id
 *   - tabpanel.aria-labelledby ↔ tab.id
 *   - roving tabindex: only the active tab is in the tab order
 *   - ArrowLeft / ArrowRight / Home / End move focus AND activate
 *   - non-active panels are hidden via the hidden attribute
 */
const TABS: TabKey[] = ["personal", "billing"];
const PANEL_IDS: Record<TabKey, string> = { personal: "perfil-panel-personal", billing: "perfil-panel-billing" };
const TAB_IDS:   Record<TabKey, string> = { personal: "perfil-tab-personal",   billing: "perfil-tab-billing"   };

export function ProfileTabs({ personal, billing, initial = "personal" }: Props) {
  const dict = useDict();
  const t = (dict.dashboard_profile as Record<string, string>);
  const [tab, setTab] = useState<TabKey>(initial);
  const tablistRef = useRef<HTMLDivElement | null>(null);

  function onKeyDown(e: React.KeyboardEvent) {
    const idx = TABS.indexOf(tab);
    let next: TabKey | null = null;
    if (e.key === "ArrowRight") next = TABS[(idx + 1) % TABS.length];
    else if (e.key === "ArrowLeft") next = TABS[(idx - 1 + TABS.length) % TABS.length];
    else if (e.key === "Home") next = TABS[0];
    else if (e.key === "End") next = TABS[TABS.length - 1];
    if (next) {
      e.preventDefault();
      setTab(next);
      // Move focus to the newly active tab so a screen reader announces it.
      const btn = tablistRef.current?.querySelector<HTMLButtonElement>(`#${TAB_IDS[next]}`);
      btn?.focus();
    }
  }

  return (
    <div>
      <div
        ref={tablistRef}
        role="tablist"
        aria-label={t.tablist_aria ?? "Profile sections"}
        onKeyDown={onKeyDown}
        style={{
          display: "flex", gap: 0,
          borderBottom: "2px solid var(--line)",
          marginTop: 22,
        }}
      >
        <TabButton
          tabKey="personal"
          active={tab === "personal"}
          onActivate={() => setTab("personal")}
        >
          {t.section_personal}
        </TabButton>
        <TabButton
          tabKey="billing"
          active={tab === "billing"}
          onActivate={() => setTab("billing")}
        >
          {t.section_billing}
        </TabButton>
      </div>
      <div
        id={PANEL_IDS.personal}
        role="tabpanel"
        aria-labelledby={TAB_IDS.personal}
        hidden={tab !== "personal"}
        tabIndex={0}
      >
        {personal}
      </div>
      <div
        id={PANEL_IDS.billing}
        role="tabpanel"
        aria-labelledby={TAB_IDS.billing}
        hidden={tab !== "billing"}
        tabIndex={0}
      >
        {billing}
      </div>
    </div>
  );
}

function TabButton({ tabKey, active, onActivate, children }: {
  tabKey: TabKey; active: boolean; onActivate: () => void; children: ReactNode;
}) {
  return (
    <button
      type="button"
      id={TAB_IDS[tabKey]}
      role="tab"
      aria-selected={active}
      aria-controls={PANEL_IDS[tabKey]}
      tabIndex={active ? 0 : -1}
      onClick={onActivate}
      style={{
        background: "transparent",
        border: 0,
        padding: "12px 22px",
        cursor: "pointer",
        fontFamily: "inherit",
        fontSize: 14,
        fontWeight: active ? 700 : 500,
        color: active ? "var(--orange)" : "var(--muted)",
        borderBottom: active ? "2px solid var(--orange)" : "2px solid transparent",
        marginBottom: -2,
        transition: "color 0.15s, border-color 0.15s",
      }}
    >
      {children}
    </button>
  );
}
