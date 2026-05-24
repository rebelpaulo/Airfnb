export const eur = new Intl.NumberFormat("pt-PT", {
  style: "currency",
  currency: "EUR",
  maximumFractionDigits: 0,
});

export function money(v: number | string | null | undefined) {
  const n = typeof v === "string" ? Number(v) : (v ?? 0);
  if (!isFinite(n)) return "—";
  return eur.format(n);
}
