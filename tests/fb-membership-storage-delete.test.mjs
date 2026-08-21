import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const [route, caller, shared, baseline] = await Promise.all([
  readFile("app/api/me/fb-membership/route.ts", "utf8"),
  readFile("app/dashboard/conta/DeleteAccountButton.tsx", "utf8"),
  readFile("supabase/migrations/20260821121634_shared_project_auth_boundary.sql", "utf8"),
  readFile("scripts/migrations/apply/20260821124724_indigo_shared_project_baseline.sql", "utf8"),
]);

test("membership deletion is a same-origin authenticated server operation", () => {
  assert.match(route, /origin !== request\.nextUrl\.origin/u);
  assert.match(route, /fetchSite !== null && fetchSite !== "same-origin"/u);
  assert.match(route, /supabase\.auth\.getUser\(\)/u);
  assert.match(route, /SUPABASE_SERVICE_ROLE_KEY/u);
  assert.doesNotMatch(caller, /\.rpc\("airfnb_self_delete"\)/u);
  assert.match(caller, /fetch\("\/api\/me\/fb-membership"[\s\S]*method: "POST"/u);
});

test("server removes every user-owned media prefix before and after tombstoning", () => {
  assert.match(route, /purgePrefix\("airfnb-avatars", userId\)/u);
  assert.match(route, /purgePrefix\("airfnb-truck-images", truckId\)/u);
  assert.match(route, /purgePrefix\("airfnb-documents", truckId\)/u);
  assert.match(route, /await purgeMembershipMedia\(user\.id, liveTruckIds\)[\s\S]*\.rpc\("airfnb_self_delete"\)[\s\S]*\.rpc\("airfnb_self_delete_storage_prefixes"\)[\s\S]*await purgeMembershipMedia\(user\.id, allTruckIds\)/u);
  assert.match(route, /await listObjects\(bucket, prefix, remaining\)[\s\S]*remaining\.length > 0/u);
});

test("tombstone retains retry prefixes and Storage writes require a live profile", () => {
  for (const sql of [shared, baseline]) {
    assert.match(sql, /storage_truck_ids uuid\[\][^\n]*(?:not null|NOT NULL)/u);
    assert.match(sql, /airfnb_self_delete\(\)[\s\S]*returns void/iu);
    assert.match(sql, /airfnb_self_delete_storage_prefixes\(\)[\s\S]*returns uuid\[\]/iu);
    assert.match(sql, /insert into public\.airfnb_membership_tombstones \(user_id, storage_truck_ids\)/iu);
    for (const policy of [
      "airfnb_avatars_owner_insert",
      "airfnb_avatars_owner_update",
      "airfnb_avatars_owner_delete",
      "airfnb_truck_images_owner_insert",
      "airfnb_truck_images_owner_update",
      "airfnb_truck_images_owner_delete",
      "airfnb_documents_owner_read",
      "airfnb_documents_owner_insert",
      "airfnb_documents_owner_update",
      "airfnb_documents_owner_delete",
    ]) {
      assert.match(sql, new RegExp(`${policy}[\\s\\S]{0,1500}airfnb_profiles`, "iu"));
    }
  }
});
