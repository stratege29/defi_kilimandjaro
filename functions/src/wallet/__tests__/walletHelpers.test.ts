/**
 * Tests unitaires des constantes anti-cheat du wallet.
 *
 * Les tests d'intégration (bootstrapWallet, unlockPack, creditCauris,
 * syncWallet) avec Firestore emulator sont dans
 * `__tests__/integration/wallet.integration.test.ts`.
 */

import {
  CAURIS_CREDIT_MAX_BY_SOURCE,
  CAURIS_CREDIT_DAILY_COUNT_MAX,
  CAURIS_MAX_BALANCE,
  CAURIS_BOOTSTRAP_CAP,
  utcDayKey,
} from "../walletHelpers";

describe("wallet anti-cheat constants", () => {
  describe("CAURIS_CREDIT_MAX_BY_SOURCE", () => {
    it("définit un cap pour chaque source légitime", () => {
      const expectedSources = [
        "win",
        "daily",
        "rewarded",
        "streak",
        "iap",
        "manual",
      ];
      for (const source of expectedSources) {
        expect(CAURIS_CREDIT_MAX_BY_SOURCE[source]).toBeGreaterThan(0);
      }
    });

    it("caps reasonable pour win/daily (> remote config defaults)", () => {
      // Defaults remote : eco_win_reward_base=30, daily base=100+streak=300
      expect(CAURIS_CREDIT_MAX_BY_SOURCE.win).toBeGreaterThanOrEqual(100);
      expect(CAURIS_CREDIT_MAX_BY_SOURCE.daily).toBeGreaterThanOrEqual(400);
    });

    it("iap cap couvre le plus gros pack (coins_pack_4999)", () => {
      expect(CAURIS_CREDIT_MAX_BY_SOURCE.iap).toBeGreaterThanOrEqual(4999);
    });

    it("rewarded cap > eco_rewarded_video_bonus (50) avec marge", () => {
      expect(CAURIS_CREDIT_MAX_BY_SOURCE.rewarded).toBeGreaterThanOrEqual(100);
    });

    it("aucun cap ne dépasse le solde max global", () => {
      for (const cap of Object.values(CAURIS_CREDIT_MAX_BY_SOURCE)) {
        expect(cap).toBeLessThanOrEqual(CAURIS_MAX_BALANCE);
      }
    });

    it("daily cap couvre 100 base + bonus palier J30 (1000)", () => {
      // Régression : le cap était à 800 alors que le bonus J30 (1000) +
      // base (100) = 1100 → un joueur légitime à J30 était rejeté serveur.
      expect(CAURIS_CREDIT_MAX_BY_SOURCE.daily).toBeGreaterThanOrEqual(1100);
    });
  });

  describe("CAURIS_CREDIT_DAILY_COUNT_MAX (backstop fréquence)", () => {
    it("définit un plafond de fréquence positif pour chaque source", () => {
      const expectedSources = [
        "win",
        "daily",
        "rewarded",
        "streak",
        "iap",
        "manual",
      ];
      for (const source of expectedSources) {
        expect(CAURIS_CREDIT_DAILY_COUNT_MAX[source]).toBeGreaterThan(0);
      }
    });

    it("borne défi du jour et streak à ~1/jour (marge re-essai)", () => {
      // 1 défi + 1 streak par jour calendaire ; une petite marge tolère un
      // re-essai réseau, mais reste loin du farming.
      expect(CAURIS_CREDIT_DAILY_COUNT_MAX.daily).toBeLessThanOrEqual(3);
      expect(CAURIS_CREDIT_DAILY_COUNT_MAX.streak).toBeLessThanOrEqual(3);
    });

    it("tolère le cap client rewarded (5/jour) + double + marge RC", () => {
      expect(CAURIS_CREDIT_DAILY_COUNT_MAX.rewarded).toBeGreaterThanOrEqual(10);
    });
  });

  describe("utcDayKey", () => {
    it("formate une date en YYYY-MM-DD (UTC)", () => {
      const key = utcDayKey(new Date("2026-06-29T23:30:00.000Z"));
      expect(key).toBe("2026-06-29");
    });

    it("bascule de jour à minuit UTC, pas en heure locale", () => {
      // 2026-06-29T23:59Z et 2026-06-30T00:01Z sont deux jours distincts.
      expect(utcDayKey(new Date("2026-06-29T23:59:00.000Z"))).toBe("2026-06-29");
      expect(utcDayKey(new Date("2026-06-30T00:01:00.000Z"))).toBe("2026-06-30");
    });
  });

  describe("CAURIS_MAX_BALANCE", () => {
    it("est plafonné à < INT_MAX JS pour éviter overflow", () => {
      // 999_999 << Number.MAX_SAFE_INTEGER (2^53 - 1)
      expect(CAURIS_MAX_BALANCE).toBeLessThan(Number.MAX_SAFE_INTEGER);
      expect(CAURIS_MAX_BALANCE).toBeGreaterThanOrEqual(100_000);
    });
  });

  describe("CAURIS_BOOTSTRAP_CAP", () => {
    it("est raisonnable (> eco_initial_cauris=120, < achats premium)", () => {
      expect(CAURIS_BOOTSTRAP_CAP).toBeGreaterThanOrEqual(500);
      // Doit être < le plus petit IAP pack pour ne pas permettre un client
      // modifié de se créer un wallet équivalent à un achat
      expect(CAURIS_BOOTSTRAP_CAP).toBeLessThanOrEqual(5_000);
    });
  });
});
