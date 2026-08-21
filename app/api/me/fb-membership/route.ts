import { NextResponse, type NextRequest } from "next/server";
import { supabaseAdmin, supabaseServer } from "@/lib/supabase/server";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PAGE_SIZE = 1000;
const REMOVE_BATCH_SIZE = 100;
const MAX_OBJECTS_PER_PREFIX = 10_000;
const MAX_FOLDER_DEPTH = 16;

type StorageBucket = ReturnType<typeof supabaseAdmin>["storage"] extends {
  from(bucket: string): infer Bucket;
} ? Bucket : never;

function refuseCrossOrigin(request: NextRequest): NextResponse | null {
  const origin = request.headers.get("origin");
  const fetchSite = request.headers.get("sec-fetch-site");
  if (
    origin !== request.nextUrl.origin
    || (fetchSite !== null && fetchSite !== "same-origin")
  ) {
    return NextResponse.json(
      { error: "cross-origin membership deletion refused" },
      { status: 403, headers: { "Cache-Control": "no-store" } },
    );
  }
  return null;
}

async function listObjects(
  bucket: StorageBucket,
  folder: string,
  paths: string[],
  depth = 0,
): Promise<void> {
  if (depth > MAX_FOLDER_DEPTH) {
    throw new Error("storage folder depth exceeds deletion limit");
  }

  for (let offset = 0; ; offset += PAGE_SIZE) {
    const { data, error } = await bucket.list(folder, {
      limit: PAGE_SIZE,
      offset,
      sortBy: { column: "name", order: "asc" },
    });
    if (error) throw new Error(`storage list failed: ${error.message}`);

    for (const entry of data ?? []) {
      const path = `${folder}/${entry.name}`;
      if (entry.id) {
        paths.push(path);
        if (paths.length > MAX_OBJECTS_PER_PREFIX) {
          throw new Error("storage prefix exceeds deletion limit");
        }
      } else {
        await listObjects(bucket, path, paths, depth + 1);
      }
    }

    if ((data?.length ?? 0) < PAGE_SIZE) return;
  }
}

async function purgePrefix(bucketName: string, prefix: string): Promise<void> {
  const bucket = supabaseAdmin().storage.from(bucketName);

  // The first pass removes the current snapshot. Re-listing is mandatory: it
  // catches partial Storage API deletes and any upload racing the pre-delete
  // phase. After the tombstone commits, Storage write policies require the
  // F&B profile and prevent new objects from appearing.
  for (let pass = 0; pass < 3; pass += 1) {
    const paths: string[] = [];
    await listObjects(bucket, prefix, paths);
    if (paths.length === 0) return;

    for (let index = 0; index < paths.length; index += REMOVE_BATCH_SIZE) {
      const batch = paths.slice(index, index + REMOVE_BATCH_SIZE);
      const { error } = await bucket.remove(batch);
      if (error) throw new Error(`storage remove failed: ${error.message}`);
    }
  }

  const remaining: string[] = [];
  await listObjects(bucket, prefix, remaining);
  if (remaining.length > 0) {
    throw new Error("storage deletion postcondition failed");
  }
}

async function purgeMembershipMedia(userId: string, truckIds: string[]): Promise<void> {
  await purgePrefix("airfnb-avatars", userId);
  for (const truckId of truckIds) {
    if (!UUID_RE.test(truckId)) throw new Error("invalid truck deletion prefix");
    await purgePrefix("airfnb-truck-images", truckId);
    await purgePrefix("airfnb-documents", truckId);
  }
}

export async function POST(request: NextRequest) {
  const refused = refuseCrossOrigin(request);
  if (refused) return refused;

  if (
    !process.env.NEXT_PUBLIC_SUPABASE_URL
    || !process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
    || !process.env.SUPABASE_SERVICE_ROLE_KEY
  ) {
    return NextResponse.json(
      { error: "membership deletion is unavailable" },
      { status: 503, headers: { "Cache-Control": "no-store" } },
    );
  }

  const supabase = await supabaseServer();
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user || !UUID_RE.test(user.id)) {
    return NextResponse.json(
      { error: "authentication required" },
      { status: 401, headers: { "Cache-Control": "no-store" } },
    );
  }

  try {
    const { data: trucks, error: trucksError } = await (supabase as any)
      .from("airfnb_trucks")
      .select("id")
      .eq("owner_id", user.id);
    if (trucksError) throw new Error(trucksError.message);

    const liveTruckIds = (trucks ?? [])
      .map((truck: { id?: unknown }) => truck.id)
      .filter((id: unknown): id is string => typeof id === "string" && UUID_RE.test(id));

    // Remove the current snapshot before mutating SQL. If Storage is
    // unavailable, the membership stays intact and the operation is retryable.
    await purgeMembershipMedia(user.id, liveTruckIds);

    // The RPC atomically tombstones the membership, removes/anonymizes SQL
    // data, and returns the durable list of owned truck prefixes. On a retry it
    // returns the same list even though the profile and some trucks are gone.
    const { error: deleteError } = await (supabase as any)
      .rpc("airfnb_self_delete");
    if (deleteError) throw new Error(deleteError.message);

    const { data: storedTruckIds, error: prefixesError } = await (supabase as any)
      .rpc("airfnb_self_delete_storage_prefixes");
    if (prefixesError) throw new Error(prefixesError.message);

    const allTruckIds = Array.from(new Set([
      ...liveTruckIds,
      ...(Array.isArray(storedTruckIds) ? storedTruckIds : []),
    ])).filter((id): id is string => typeof id === "string" && UUID_RE.test(id));

    // Close the race between the initial Storage snapshot and the tombstone.
    // After this pass, write policies reject the now profile-less identity.
    await purgeMembershipMedia(user.id, allTruckIds);

    return NextResponse.json(
      { ok: true },
      { status: 200, headers: { "Cache-Control": "no-store" } },
    );
  } catch (error) {
    console.error("F&B membership deletion failed", error);
    return NextResponse.json(
      { error: "membership deletion failed; retry safely" },
      { status: 502, headers: { "Cache-Control": "no-store" } },
    );
  }
}
