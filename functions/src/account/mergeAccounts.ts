/**
 * `mergeAccounts` — fusionne l'identité d'un ancien uid (anonyme abandonné) vers
 * l'uid courant, lors d'un switch de compte (liaison Google/Apple « déjà utilisée »)
 * ou d'une re-anonymisation. Empêche la perte de pseudo / progression / cauris.
 *
 * Sécurité : l'appelant (= `toUid`, le compte conservé) fournit l'**ID token** de
 * l'ancien uid `fromUid`, capturé AVANT le switch. On le vérifie → preuve que
 * l'appelant contrôlait bien `fromUid` (sinon on pourrait voler les cauris d'autrui).
 *
 * Politique de fusion (anti-abus) :
 *   - cauris : MAX(from, to) (pas de somme → pas de farming de bootstrap), packs : union.
 *   - pseudo / avatar : repris si la cible n'en a pas.
 *   - stats ELO + duels : repris seulement si la cible n'a jamais duellé.
 *   - puis purge du `fromUid` (profil + users/ + user Auth anonyme abandonné).
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { requireAuth } from "../utils/auth";
import { walletDocRef, auditCollectionRef, CAURIS_MAX_BALANCE } from "../wallet/walletHelpers";

export const mergeAccounts = onCall(
  { region: "europe-west1", enforceAppCheck: false, cors: true },
  async (req): Promise<{ ok: true; merged: boolean; fromUid?: string; reason?: string }> => {
    const toUid = requireAuth(req.auth);
    const fromToken = (req.data?.fromIdToken as string) || "";
    if (!fromToken) throw new HttpsError("invalid-argument", "fromIdToken requis.");

    let fromUid: string;
    try { fromUid = (await getAuth().verifyIdToken(fromToken)).uid; }
    catch { throw new HttpsError("permission-denied", "Token de l'ancien compte invalide ou expiré."); }
    if (fromUid === toUid) return { ok: true, merged: false, reason: "same-uid" };

    const db = getFirestore();

    // 1) Profil : pseudo/avatar si la cible n'en a pas ; stats si jamais duellé.
    const [fromP, toP] = await Promise.all([
      db.collection("profiles").doc(fromUid).get(),
      db.collection("profiles").doc(toUid).get(),
    ]);
    const fp = (fromP.exists ? fromP.data() : {}) as Record<string, unknown>;
    const tp = (toP.exists ? toP.data() : {}) as Record<string, unknown>;
    const upd: Record<string, unknown> = {};
    if (!tp.display_name && fp.display_name) {
      upd.display_name = fp.display_name;
      upd.display_name_updated_at = fp.display_name_updated_at ?? FieldValue.serverTimestamp();
    }
    if (!tp.avatar_id && fp.avatar_id) upd.avatar_id = fp.avatar_id;
    if (tp.elo == null && fp.elo != null) {
      for (const k of ["elo", "peakElo", "totalDuels", "wins", "losses", "createdAt", "lastDuelAt"]) {
        if (fp[k] != null) upd[k] = fp[k];
      }
    }
    if (Object.keys(upd).length) await db.collection("profiles").doc(toUid).set(upd, { merge: true });

    // 2) Historique de duels : copié si la cible n'en a aucun.
    const toHist = await db.collection("profiles").doc(toUid).collection("duel_history").limit(1).get();
    if (toHist.empty) {
      const fromHist = await db.collection("profiles").doc(fromUid).collection("duel_history")
        .orderBy("finished_at", "desc").limit(100).get();
      let batch = db.batch(), n = 0;
      for (const d of fromHist.docs) {
        batch.set(db.collection("profiles").doc(toUid).collection("duel_history").doc(d.id), d.data());
        if (++n % 400 === 0) { await batch.commit(); batch = db.batch(); }
      }
      if (n > 0) await batch.commit();
    }

    // 3) Wallet : MAX des cauris, union des packs, + audit sur la cible.
    const fromW = await walletDocRef(fromUid).get();
    if (fromW.exists) {
      const fw = fromW.data() as { cauris?: number; owned_packs?: string[] };
      await db.runTransaction(async (tx) => {
        const tSnap = await tx.get(walletDocRef(toUid));
        const tw = (tSnap.exists ? tSnap.data() : null) as { cauris?: number; owned_packs?: string[]; version?: number } | null;
        const before = tw?.cauris ?? 0;
        const after = Math.min(CAURIS_MAX_BALANCE, Math.max(before, fw.cauris ?? 0));
        const packs = Array.from(new Set([...(tw?.owned_packs ?? []), ...(fw.owned_packs ?? [])]));
        const vBefore = tw?.version ?? 0;
        if (tSnap.exists) {
          tx.update(walletDocRef(toUid), { cauris: after, owned_packs: packs, version: vBefore + 1, updated_at: FieldValue.serverTimestamp() });
        } else {
          tx.set(walletDocRef(toUid), {
            cauris: after, owned_packs: packs, version: 1,
            created_at: FieldValue.serverTimestamp(), updated_at: FieldValue.serverTimestamp(),
            last_sync_at: FieldValue.serverTimestamp(), bootstrap_source: "merge",
          });
        }
        tx.set(auditCollectionRef(toUid).doc(), {
          type: "merge", source: "merge", amount: after - before, actor_uid: toUid,
          cauris_before: before, cauris_after: after, wallet_version_before: vBefore, wallet_version_after: vBefore + 1,
          details: { from_uid: fromUid }, timestamp: FieldValue.serverTimestamp(),
        });
      });
    }

    // 4) Purge de l'ancien uid (données + compte Auth anonyme abandonné).
    try {
      await db.collection("profiles").doc(fromUid).delete();
      await db.recursiveDelete(db.collection("users").doc(fromUid));
      const fu = await getAuth().getUser(fromUid).catch(() => null);
      if (fu && (fu.providerData || []).length === 0) await getAuth().deleteUser(fromUid);
    } catch (e) {
      logger.warn("mergeAccounts: cleanup partiel", { fromUid, error: (e as Error).message });
    }

    logger.info("mergeAccounts: done", { fromUid, toUid });
    return { ok: true, merged: true, fromUid };
  }
);
