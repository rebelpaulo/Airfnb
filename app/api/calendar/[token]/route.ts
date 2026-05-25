// Public ICS endpoint. Anyone with the booking's ics_token (issued at
// booking-create time, 16-char base32) can fetch the calendar invite —
// same security model as a shared Outlook/Google invite link. The path
// extension '.ics' isn't part of Next routing here; the response sets
// content-type so calendar apps recognise the body.
import { NextResponse, type NextRequest } from "next/server";
import { supabaseAdmin } from "@/lib/supabase/server";

export const runtime = "nodejs";

const APP_URL = process.env.APP_URL ?? process.env.NEXT_PUBLIC_APP_URL ?? "https://airfnb.vercel.app";

function ics_escape(s: string): string {
  // RFC 5545 §3.3.11 — escape \, ; , and newlines inside TEXT values.
  // Normalize all CR/CRLF to LF *before* escaping so a value containing a
  // raw \r can't break out of a property line and inject extra fields.
  return s
    .replace(/\r\n?/g, "\n")
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\n/g, "\\n");
}
function ics_date(iso: string): string {
  // UTC basic format: 20260525T143000Z
  return new Date(iso).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

export async function GET(_req: NextRequest, { params }: { params: Promise<{ token: string }> }) {
  // Strip optional .ics suffix — calendar apps frequently insist on the
  // extension before treating the URL as a feed.
  const { token: rawToken } = await params;
  const token = rawToken.replace(/\.ics$/i, "");

  const supa = supabaseAdmin();
  const { data, error } = await (supa as any).rpc("airfnb_booking_by_ics_token", { p_token: token });
  if (error || !(data as any[])?.length) {
    return new NextResponse("Calendar event not found", { status: 404 });
  }
  const b = (data as any[])[0];
  // airfnb_bookings.starts_at is nullable in the schema. Without this guard,
  // new Date(null).toISOString() would emit 19700101T000000Z and the consumer
  // would happily render an event at the Unix epoch — fail fast instead.
  if (!b.starts_at) {
    return new NextResponse("Booking has no start time", { status: 422 });
  }

  const uid = `${b.id}@airfnb`;
  const title  = `Air F&B — ${b.title}${b.truck_names ? ` (${b.truck_names})` : ""}`;
  const location = b.city ?? "";
  const desc = `${title}\n\nReserva via ${APP_URL}`;

  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Air F&B//Marketplace//PT",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "BEGIN:VEVENT",
    `UID:${uid}`,
    `DTSTAMP:${ics_date(new Date().toISOString())}`,
    `DTSTART:${ics_date(b.starts_at)}`,
    `DTEND:${ics_date(b.ends_at)}`,
    `SUMMARY:${ics_escape(title)}`,
    location ? `LOCATION:${ics_escape(location)}` : "",
    `DESCRIPTION:${ics_escape(desc)}`,
    `URL:${APP_URL}/dashboard/organizer/pedidos/${b.id}`,
    "END:VEVENT",
    "END:VCALENDAR",
  ].filter(Boolean).join("\r\n");

  return new NextResponse(lines, {
    status: 200,
    headers: {
      "content-type":        "text/calendar; charset=utf-8",
      "content-disposition": `inline; filename="airfnb-${token}.ics"`,
      "cache-control":       "private, max-age=300",
    },
  });
}
