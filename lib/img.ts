export const TRUCK_PLACEHOLDER = "/truck-placeholder.svg";

export function truckCover(url: string | null | undefined): string {
  if (!url || typeof url !== "string") return TRUCK_PLACEHOLDER;
  return url;
}
