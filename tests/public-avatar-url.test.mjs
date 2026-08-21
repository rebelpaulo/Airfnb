import assert from "node:assert/strict";
import test from "node:test";
import { publicAvatarUrl } from "../lib/public-avatar-url.ts";

const base = "https://project-ref.supabase.co";
const owner = "11111111-1111-4111-8111-111111111111";

test("accepts an exact first-party public avatar object URL", () => {
  const value = `${base}/storage/v1/object/public/airfnb-avatars/${owner}/avatar-1.webp`;
  assert.equal(publicAvatarUrl(value, base), value);
});

test("rejects third-party, wrong-bucket and ambiguous avatar URLs", () => {
  const attacks = [
    `https://tracker.example/avatar/${owner}/pixel.png`,
    `${base}/storage/v1/object/public/airfnb-truck-images/${owner}/avatar.png`,
    `${base}/storage/v1/object/public/airfnb-avatars/not-a-uuid/avatar.png`,
    `${base}/storage/v1/object/public/airfnb-avatars/${owner}`,
    `${base}/storage/v1/object/public/airfnb-avatars/${owner}/avatar.png?track=1`,
    `${base}/storage/v1/object/public/airfnb-avatars/${owner}/avatar.png#track`,
    `${base}/storage/v1/object/public/airfnb-avatars/${owner}/avatar%2Fpixel.png`,
    `${base}/storage/v1/object/public/airfnb-avatars/${owner}/avatar%5Cpixel.png`,
    `${base}/storage/v1/object/public/airfnb-avatars/${owner}/avatar),url.png`,
    `https://user:password@project-ref.supabase.co/storage/v1/object/public/airfnb-avatars/${owner}/avatar.png`,
    `//tracker.example/storage/v1/object/public/airfnb-avatars/${owner}/avatar.png`,
    "data:image/png;base64,AAAA",
    "javascript:alert(1)",
  ];

  for (const attack of attacks) assert.equal(publicAvatarUrl(attack, base), null, attack);
  assert.equal(publicAvatarUrl(`${base}/storage/v1/object/public/airfnb-avatars/${owner}/avatar.png`, undefined), null);
  assert.equal(publicAvatarUrl(`${base}/storage/v1/object/public/airfnb-avatars/${owner}/avatar.png`, "not a URL"), null);
  assert.equal(publicAvatarUrl(`${base}/storage/v1/object/public/airfnb-avatars/${owner}/avatar.png`, `${base}/nested`), null);
  assert.equal(publicAvatarUrl(`${base}/storage/v1/object/public/airfnb-avatars/${owner}/${"a".repeat(2048)}`, base), null);
});

test("all avatar UI sinks use the shared validator", async () => {
  const { readFile } = await import("node:fs/promises");
  const [layout, upload, catalogue] = await Promise.all([
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../components/AvatarUpload.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/catalogo/[slug]/page.tsx", import.meta.url), "utf8"),
  ]);

  assert.match(layout, /avatarUrl = publicAvatarUrl\(/);
  assert.match(upload, /publicAvatarUrl\(initialUrl,/);
  assert.match(upload, /const safePublicUrl = publicAvatarUrl\(publicUrl,/);
  assert.match(catalogue, /const ownerAvatarUrl = publicAvatarUrl\(/);
  assert.doesNotMatch(catalogue, /src=\{truck\.owner\.avatar_url\}/);
});
