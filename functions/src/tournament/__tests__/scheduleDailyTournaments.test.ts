/**
 * Tests des helpers purs de scheduleDailyTournaments (créneaux + noms).
 */

import {
  slotsForDate,
  pickChicName,
  CHIC_NAMES,
  WEEKEND_SLOTS,
} from "../scheduleDailyTournaments";

describe("slotsForDate", () => {
  // 2026-07-01 = mercredi (semaine) ; 2026-07-04 = samedi, 07-05 = dimanche.
  test("jour de semaine → 12h30 et 19h00", () => {
    const wed = new Date(Date.UTC(2026, 6, 1));
    expect(wed.getUTCDay()).toBe(3);
    expect(slotsForDate(wed)).toEqual([
      { hh: 12, mm: 30 },
      { hh: 19, mm: 0 },
    ]);
  });

  test("samedi → 8 créneaux de 08h à 22h toutes les 2 h", () => {
    const sat = new Date(Date.UTC(2026, 6, 4));
    expect(sat.getUTCDay()).toBe(6);
    const slots = slotsForDate(sat);
    expect(slots).toHaveLength(WEEKEND_SLOTS.length);
    expect(slots[0]).toEqual({ hh: 8, mm: 0 });
    expect(slots[slots.length - 1]).toEqual({ hh: 22, mm: 0 });
    // pas de doublon, écart de 2 h
    for (let i = 1; i < slots.length; i++) {
      expect(slots[i].hh - slots[i - 1].hh).toBe(2);
    }
  });

  test("dimanche = week-end aussi", () => {
    const sun = new Date(Date.UTC(2026, 6, 5));
    expect(sun.getUTCDay()).toBe(0);
    expect(slotsForDate(sun)).toHaveLength(8);
  });
});

describe("pickChicName", () => {
  test("retourne un nom du pool", () => {
    const d = new Date(Date.UTC(2026, 6, 4));
    for (let i = 0; i < 8; i++) {
      expect(CHIC_NAMES).toContain(pickChicName(d, i));
    }
  });

  test("varie entre créneaux consécutifs (rotation)", () => {
    const d = new Date(Date.UTC(2026, 6, 4));
    expect(pickChicName(d, 0)).not.toBe(pickChicName(d, 1));
  });

  test("déterministe pour un même (jour, créneau)", () => {
    const d = new Date(Date.UTC(2026, 6, 4));
    expect(pickChicName(d, 3)).toBe(pickChicName(d, 3));
  });
});
