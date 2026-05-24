import type { AirfnbDatabase } from "@/types/database";

type EventKind = AirfnbDatabase["public"]["Enums"]["airfnb_event_kind"];

const RATIO: Record<EventKind, number> = {
  wedding: 120,
  corporate: 150,
  festival: 200,
  conference: 100,
  birthday: 130,
  private: 130,
  other: 150,
};

export function recommendSlots(kind: EventKind, pax: number) {
  return Math.max(1, Math.ceil(pax / RATIO[kind]));
}
