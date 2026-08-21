import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const [layout, sidebar, styles] = await Promise.all([
  readFile(path.join(ROOT, "app/dashboard/layout.tsx"), "utf8"),
  readFile(path.join(ROOT, "components/DashboardSidebar.tsx"), "utf8"),
  readFile(path.join(ROOT, "app/globals.css"), "utf8"),
]);

test("dashboard shell delegates desktop and mobile geometry to responsive classes", () => {
  assert.match(layout, /<div className="dashboard-shell">/);
  assert.match(layout, /<main className="dashboard-main">\{children\}<\/main>/);
  assert.doesNotMatch(layout, /gridTemplateColumns|style=\{\{/);
  assert.match(styles, /\.dashboard-shell\s*\{[\s\S]*?grid-template-columns:\s*260px minmax\(0, 1fr\)/);
  assert.match(styles, /\.dashboard-main\s*\{\s*min-width:\s*0/);
  assert.match(styles, /@media \(max-width:\s*768px\)[\s\S]*?\.dashboard-shell\s*\{[\s\S]*?display:\s*block/);
  assert.match(styles, /@media \(max-width:\s*768px\)[\s\S]*?\.dashboard-main\s*\{[\s\S]*?width:\s*100%[\s\S]*?min-width:\s*0/);
});

test("mobile dashboard uses a compact native disclosure while desktop keeps the role-aware sidebar", () => {
  assert.match(sidebar, /<aside className="dashboard-sidebar">/);
  assert.match(sidebar, /<div className="dashboard-sidebar__desktop">/);
  assert.match(sidebar, /<details className="dashboard-sidebar__mobile">/);
  assert.match(sidebar, /<summary className="dashboard-sidebar__summary">/);
  assert.match(sidebar, /<DashboardNavigation groups=\{groups\} pathname=\{pathname\} dict=\{dict\}/);
  assert.match(sidebar, /aria-current=\{active \? "page" : undefined\}/);
  assert.match(styles, /\.dashboard-sidebar__mobile\s*\{\s*display:\s*none/);
  assert.match(styles, /@media \(max-width:\s*768px\)[\s\S]*?\.dashboard-sidebar__desktop\s*\{\s*display:\s*none[\s\S]*?\.dashboard-sidebar__mobile\s*\{\s*display:\s*block/);
  assert.match(styles, /@media \(max-width:\s*768px\)[\s\S]*?\.dashboard-sidebar\s*\{[\s\S]*?top:\s*72px[\s\S]*?width:\s*100%[\s\S]*?height:\s*auto/);
});

test("dashboard navigation retains keyboard focus and reduced-motion support", () => {
  assert.match(styles, /summary:focus-visible/);
  assert.match(styles, /@media \(prefers-reduced-motion:\s*reduce\)[\s\S]*?\.dashboard-sidebar__link/);
  assert.match(styles, /\.dashboard-sidebar__link\s*\{[\s\S]*?min-height:\s*44px/);
});
