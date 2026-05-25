"use client";

import { useState, type ReactNode } from "react";
import { useDict } from "@/components/DictProvider";

type Props = {
  /** Personal tab body (form). */
  personal: ReactNode;
  /** Billing tab body (form). */
  billing: ReactNode;
  /** Which tab to open initially — handy when redirecting back after save. */
  initial?: "personal" | "billing";
};

/**
 * Tab switcher for /dashboard/perfil. Each tab is a separate <form> with
 * its own server action so saving one tab doesn't blank the other.
 */
export function ProfileTabs({ personal, billing, initial = "personal" }: Props) {
  const dict = useDict();
  const t = (dict.dashboard_profile as Record<string, string>);
  const [tab, setTab] = useState<"personal" | "billing">(initial);

  return (
    <div>
      <div role="tablist" aria-label={t.tablist_aria ?? "Profile sections"} style={{
        display: "flex", gap: 0,
        borderBottom: "2px solid var(--line)",
        marginTop: 22,
      }}>
        <TabButton active={tab === "personal"} onClick={() => setTab("personal")}>
          {t.section_personal}
        </TabButton>
        <TabButton active={tab === "billing"} onClick={() => setTab("billing")}>
          {t.section_billing}
        </TabButton>
      </div>
      <div role="tabpanel" hidden={tab !== "personal"} style={{ marginTop: 0 }}>{personal}</div>
      <div role="tabpanel" hidden={tab !== "billing"}  style={{ marginTop: 0 }}>{billing}</div>
    </div>
  );
}

function TabButton({ active, onClick, children }: { active: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      role="tab"
      aria-selected={active}
      onClick={onClick}
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
