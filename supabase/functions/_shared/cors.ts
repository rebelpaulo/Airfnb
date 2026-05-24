// Allowed origins come from the ALLOWED_ORIGINS env var, comma-separated.
// Wildcard ("*") is only used when explicitly opted in via ALLOWED_ORIGINS="*",
// because shared helpers can be reached from privileged workflows.
const ALLOWED = (Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",").map(s => s.trim()).filter(Boolean);
function allowOrigin(reqOrigin: string | null): string {
  if (ALLOWED.length === 0) return "null";   // safer default than "*"
  if (ALLOWED.includes("*")) return "*";
  if (reqOrigin && ALLOWED.includes(reqOrigin)) return reqOrigin;
  return "null";
}
export function corsHeadersFor(req: Request): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": allowOrigin(req.headers.get("origin")),
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, stripe-signature",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
// Legacy export kept for backward compatibility; callers should migrate to corsHeadersFor(req).
export const corsHeaders = {
  "Access-Control-Allow-Origin": "null",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, stripe-signature",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function handlePreflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return null;
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}
