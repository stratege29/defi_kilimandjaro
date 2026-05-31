/**
 * Tests unitaires des constantes anti-cheat du wallet.
 *
 * Les tests d'intégration (bootstrapWallet, unlockPack, creditCauris,
 * syncWallet) avec Firestore emulator sont dans
 * `__tests__/integration/wallet.integration.test.ts`.
 */

import {
  CAURIS_CREDIT_MAX_BY_SOURCE,
  CAURIS_MAX_BALANCE,
  CAURIS_BOOTSTRAP_CAP,
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
