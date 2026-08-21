import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

const [sidebarSource, layoutSource] = await Promise.all([
  readFile(path.join(ROOT, "components/DashboardSidebar.tsx"), "utf8"),
  readFile(path.join(ROOT, "app/dashboard/layout.tsx"), "utf8"),
]);

test("dashboard navigation uses the exact database role union", () => {
  assert.match(
    sidebarSource,
    /export type DashboardRole\s*=\s*"organizer"\s*\|\s*"owner"\s*\|\s*"admin"\s*\|\s*"staff"\s*\|\s*null\s*;/,
  );
  assert.doesNotMatch(sidebarSource, /role\s*:\s*string\b/);
  assert.match(
    sidebarSource,
    /if \(role === "admin" \|\| role === "staff"\) \{[\s\S]*?\{ section: "admin", items: \[[\s\S]*?\{ href: "\/admin",\s+icon: "admin_panel_settings", key: "admin_dashboard" \},[\s\S]*?\{ href: "\/admin\/trucks",\s+icon: "fact_check",\s+key: "admin_trucks" \},[\s\S]*?\{ href: "\/admin\/definicoes", icon: "tune",\s+key: "admin_settings" \},[\s\S]*?\{ section: "shared", items: shared \},[\s\S]*?\];\s*\}/,
  );
});

test("dashboard layout preserves auth and profile lookup while passing staff through", () => {
  assert.match(
    layoutSource,
    /import \{ DashboardSidebar, type DashboardRole \} from "@\/components\/DashboardSidebar";/,
  );
  assert.match(
    layoutSource,
    /function toDashboardRole\(role: unknown\): DashboardRole \{[\s\S]*?role === "organizer" \|\|[\s\S]*?role === "owner" \|\|[\s\S]*?role === "admin" \|\|[\s\S]*?role === "staff"[\s\S]*?return role;[\s\S]*?return null;[\s\S]*?\}/,
  );
  assert.match(layoutSource, /const role = toDashboardRole\(profile\?\.role\);/);
  assert.doesNotMatch(layoutSource, /\bas\s+(?:DashboardRole|"organizer")/);
  assert.doesNotMatch(layoutSource, /role === "staff"\s*\?\s*"admin"/);

  const getUserIndex = layoutSource.indexOf("supa.auth.getUser()");
  const profileIndex = layoutSource.indexOf('.from("airfnb_profiles")');
  const normalizeRoleIndex = layoutSource.indexOf("toDashboardRole(profile?.role)");
  const sidebarIndex = layoutSource.indexOf("<DashboardSidebar role={role}");

  assert.ok(getUserIndex >= 0, "layout must keep the server getUser check");
  assert.ok(profileIndex > getUserIndex, "profile lookup must follow authentication");
  assert.ok(normalizeRoleIndex > profileIndex, "role must come from the fetched profile");
  assert.ok(sidebarIndex > normalizeRoleIndex, "the original role must reach the sidebar");
  assert.match(layoutSource, /if \(!user\) redirect\("\/login\?next=\/dashboard"\);/);
  assert.match(layoutSource, /\.select\("role, display_name, full_name"\)/);
  assert.match(layoutSource, /\.eq\("id", user\.id\)\s*\n\s*\.maybeSingle\(\)/);
  assert.doesNotMatch(layoutSource, /\.rpc\(|airfnb_is_admin|airfnb_admin_/);
});
