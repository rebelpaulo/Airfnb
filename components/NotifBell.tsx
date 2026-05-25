"use client";
import Link from "next/link";
import { useEffect, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";
import { useDict } from "@/components/DictProvider";

/**
 * Header notification bell. Shows the count of UNREAD notifications for the
 * current user, subscribed to airfnb_notifications inserts so the badge
 * updates without a page refresh.
 *
 * Defer supabaseBrowser() to useEffect — calling it at render would throw at
 * SSR/build time on misconfigured deployments (the same pattern used elsewhere
 * in this app).
 */
export function NotifBell({ userId }: { userId: string }) {
  const dict = useDict();
  const t = dict.dashboard.shared_notification_bell;
  const [unread, setUnread] = useState(0);

  useEffect(() => {
    let cancelled = false;
    const supa = supabaseBrowser();

    // Initial fetch — count head:true is cheap (server returns no rows)
    (async () => {
      const { count } = await (supa as any)
        .from("airfnb_notifications")
        .select("id", { count: "exact", head: true })
        .eq("user_id", userId)
        .is("read_at", null);
      if (!cancelled) setUnread(count ?? 0);
    })();

    // Realtime: bump on new inserts targeted at this user, decrement on
    // UPDATEs that set read_at (the user marked something read elsewhere
    // in the app — keeps the badge in sync across tabs).
    const ch = supa
      .channel(`notif:${userId}`)
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "airfnb_notifications", filter: `user_id=eq.${userId}` },
        () => setUnread((n) => n + 1),
      )
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "airfnb_notifications", filter: `user_id=eq.${userId}` },
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
  }, [userId]);

  return (
    <Link className="icon-chip" href="/dashboard/notificacoes" aria-label={`${t.aria_base}${unread ? ` (${unread} ${t.aria_unread_suffix})` : ""}`}
          style={{ position: "relative" }}>
      <span className="material-symbols-outlined">notifications</span>
      {unread > 0 && (
        <span
          aria-hidden="true"
          style={{
            position: "absolute", top: 2, right: 2,
            background: "#FF4919", color: "#fff",
            fontSize: 10, fontWeight: 700,
            minWidth: 18, height: 18, borderRadius: 999,
            display: "inline-flex", alignItems: "center", justifyContent: "center",
            padding: "0 5px",
            border: "1.5px solid #fff",
          }}
        >
          {unread > 99 ? "99+" : unread}
        </span>
      )}
    </Link>
  );
}
