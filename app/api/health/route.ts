import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

function releaseIdentifier(): string {
  const commit = process.env.VERCEL_GIT_COMMIT_SHA;
  if (commit && /^[a-f\d]{7,64}$/i.test(commit)) return commit.slice(0, 12);

  const version = process.env.npm_package_version;
  if (version && /^[0-9A-Za-z.+-]{1,64}$/.test(version)) return version;

  return "development";
}

export function GET() {
  return NextResponse.json(
    { status: "ok", release: releaseIdentifier() },
    {
      headers: {
        "Cache-Control": "no-store, max-age=0",
        "X-Robots-Tag": "noindex, nofollow",
      },
    },
  );
}
