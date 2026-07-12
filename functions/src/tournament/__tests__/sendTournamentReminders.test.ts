/**
 * Tests de la fonction pure isReminderDue (fenêtre de rappel avant démarrage).
 */

import { isReminderDue, REMINDER_LEAD_MS } from "../sendTournamentReminders";

describe("isReminderDue", () => {
  const startAt = 1_000_000;

  test("faux si pas scheduled", () => {
    expect(isReminderDue("live", startAt, false, startAt - 1000)).toBe(false);
  });

  test("faux si déjà envoyé", () => {
    expect(isReminderDue("scheduled", startAt, true, startAt - 1000)).toBe(
      false
    );
  });

  test("faux avant la fenêtre (trop tôt)", () => {
    const now = startAt - REMINDER_LEAD_MS - 1;
    expect(isReminderDue("scheduled", startAt, false, now)).toBe(false);
  });

  test("vrai pile au début de la fenêtre", () => {
    const now = startAt - REMINDER_LEAD_MS;
    expect(isReminderDue("scheduled", startAt, false, now)).toBe(true);
  });

  test("vrai juste avant le démarrage", () => {
    const now = startAt - 1;
    expect(isReminderDue("scheduled", startAt, false, now)).toBe(true);
  });

  test("faux à/après start_at (déjà démarré)", () => {
    expect(isReminderDue("scheduled", startAt, false, startAt)).toBe(false);
    expect(isReminderDue("scheduled", startAt, false, startAt + 1)).toBe(
      false
    );
  });
});
