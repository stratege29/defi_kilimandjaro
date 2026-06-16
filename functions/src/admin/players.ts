/**
 * Backoffice « Joueurs / Support » — recherche, fiche, et actions support
 * (ajuster cauris, bannir, supprimer). Toutes gardées par `requireAdmin`.
 *
 * Modèle (cf investigation) :
 *   - profil  : profiles/{uid}  (elo, wins, losses, display_name, banned…)
 *   - wallet  : users/{uid}/inventory/wallet  (cauris, owned_packs, version)
 *   - audit   : users/{uid}/inventory_audit/{logId}
 *   - duels   : profiles/{uid}/duel_history/{matchId}
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getAuth, type UserRecord } from "firebase-admin/auth";
import { requireAdmin } from "../utils/auth";
import { walletDocRef, auditCollectionRef, CAURIS_MAX_BALANCE } from "../wallet/walletHelpers";

const OPTS = { region: "europe-west1" as const, enforceAppCheck: false, cors: true };

function authSummary(u: UserRecord | null) {
  if (!u) return null;
  return {
    uid: u.uid,
    email: u.email ?? null,
    emailVerified: u.emailVerified,
    disabled: u.disabled,
    displayName: u.displayName ?? null,
    providers: (u.providerData || []).map((p) => p.providerId),
    isAnonymous: (u.providerData || []).length === 0,
    createdAt: u.metadata?.creationTime ?? null,
    lastSignIn: u.metadata?.lastSignInTime ?? null,
  };
}

async function getAuthRecord(uid: string): Promise<UserRecord | null> {
  try { return await getAuth().getUser(uid); } catch { return null; }
}

async function walletOf(uid: string): Promise<{ cauris: number; owned_packs: string[]; version: number } | null> {
  const snap = await walletDocRef(uid).get();
  if (!snap.exists) return null;
  const w = snap.data() as { cauris?: number; owned_packs?: string[]; version?: number };
  return { cauris: w.cauris ?? 0, owned_packs: w.owned_packs ?? [], version: w.version ?? 0 };
}

async function lightCard(uid: string) {
  const db = getFirestore();
  const [profSnap, wallet, auth] = await Promise.all([
    db.collection("profiles").doc(uid).get(),
    walletOf(uid),
    getAuthRecord(uid),
  ]);
  const p = (profSnap.exists ? profSnap.data() : {}) as Record<string, unknown>;
  return {
    uid,
    display_name: (p.display_name as string) ?? auth?.displayName ?? null,
    elo: (p.elo as number) ?? null,
    cauris: wallet?.cauris ?? null,
    banned: p.banned === true || auth?.disabled === true,
    email: auth?.email ?? null,
    isAnonymous: auth ? (auth.providerData || []).length === 0 : null,
    hasProfile: profSnap.exists,
  };
}

/** Recherche un joueur par uid, email, ou préfixe de display_name. */
export const adminFindPlayers = onCall(OPTS, async (req): Promise<{ ok: true; players: unknown[] }> => {
  requireAdmin(req.auth);
  const q = ((req.data?.query as string) || "").trim();
  if (!q) throw new HttpsError("invalid-argument", "query requise.");
  const db = getFirestore();
  const uids = new Set<string>();

  if (q.includes("@")) {
    try { const u = await getAuth().getUserByEmail(q); uids.add(u.uid); } catch { /* none */ }
  } else {
    // uid exact ?
    if (/^[A-Za-z0-9]{20,}$/.test(q)) {
      const exists = await db.collection("profiles").doc(q).get();
      const au = await getAuthRecord(q);
      if (exists.exists || au) uids.add(q);
    }
    // préfixe de display_name (sensible à la casse)
    const snap = await db.collection("profiles")
      .where("display_name", ">=", q).where("display_name", "<=", q + "")
      .limit(15).get();
    snap.forEach((d) => uids.add(d.id));
  }
  const players = await Promise.all([...uids].slice(0, 20).map((u) => lightCard(u)));
  return { ok: true, players };
});

/** Joueurs récents — triés par dernière activité disponible (createdAt, duel, pseudo, fcm).
 * On ne se fie pas à `createdAt` seul : il n'est posé que sur certains profils. */
export const adminRecentPlayers = onCall(OPTS, async (req): Promise<{ ok: true; players: unknown[] }> => {
  requireAdmin(req.auth);
  const limit = Math.min(50, Math.max(5, Number(req.data?.limit) || 25));
  const snap = await getFirestore().collection("profiles").limit(300).get();
  const ms = (v: unknown) => (v && typeof (v as { toMillis?: () => number }).toMillis === "function" ? (v as { toMillis: () => number }).toMillis() : 0);
  const ranked = snap.docs
    .map((d) => {
      const x = d.data();
      return { uid: d.id, recency: Math.max(ms(x.createdAt), ms(x.lastDuelAt), ms(x.display_name_updated_at), ms(x.fcm_updated_at)) };
    })
    .sort((a, b) => b.recency - a.recency)
    .slice(0, limit);
  const players = await Promise.all(ranked.map((r) => lightCard(r.uid)));
  return { ok: true, players };
});

/** Fiche détaillée d'un joueur. */
export const adminGetPlayer = onCall(OPTS, async (req): Promise<{ ok: true; player: unknown }> => {
  requireAdmin(req.auth);
  const uid = (req.data?.uid as string) || "";
  if (!uid) throw new HttpsError("invalid-argument", "uid requis.");
  const db = getFirestore();
  const [profSnap, wallet, auth, duelsSnap, auditSnap] = await Promise.all([
    db.collection("profiles").doc(uid).get(),
    walletOf(uid),
    getAuthRecord(uid),
    db.collection("profiles").doc(uid).collection("duel_history").orderBy("finished_at", "desc").limit(10).get(),
    auditCollectionRef(uid).orderBy("timestamp", "desc").limit(12).get(),
  ]);
  const ts = (v: unknown) => (v && typeof (v as { toDate?: () => Date }).toDate === "function" ? (v as { toDate: () => Date }).toDate().toISOString() : v ?? null);
  const profile = profSnap.exists ? (profSnap.data() as Record<string, unknown>) : null;
  if (profile) { profile.createdAt = ts(profile.createdAt); profile.lastDuelAt = ts(profile.lastDuelAt); }
  return {
    ok: true,
    player: {
      uid,
      profile,
      auth: authSummary(auth),
      wallet,
      banned: (profile?.banned === true) || auth?.disabled === true,
      duels: duelsSnap.docs.map((d) => { const x = d.data(); return { id: d.id, ...x, finished_at: ts(x.finished_at) }; }),
      audit: auditSnap.docs.map((d) => { const x = d.data(); return { id: d.id, ...x, timestamp: ts(x.timestamp) }; }),
    },
  };
});

/** Crédite/débite des cauris (signé) avec entrée d'audit (actor = admin). */
export const adminAdjustCauris = onCall(OPTS, async (req): Promise<{ ok: true; cauris: number }> => {
  const adminUid = requireAdmin(req.auth);
  const uid = (req.data?.uid as string) || "";
  const amount = Math.trunc(Number(req.data?.amount));
  const reason = ((req.data?.reason as string) || "").slice(0, 200);
  if (!uid) throw new HttpsError("invalid-argument", "uid requis.");
  if (!Number.isFinite(amount) || amount === 0) throw new HttpsError("invalid-argument", "amount (entier non nul) requis.");

  const db = getFirestore();
  const ref = walletDocRef(uid);
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("failed-precondition", "Ce joueur n'a pas encore de wallet (aucune activité).");
    const w = snap.data() as { cauris?: number; version?: number };
    const before = w.cauris ?? 0, vBefore = w.version ?? 0;
    const after = Math.max(0, Math.min(CAURIS_MAX_BALANCE, before + amount));
    tx.update(ref, { cauris: after, version: vBefore + 1, updated_at: FieldValue.serverTimestamp() });
    tx.set(auditCollectionRef(uid).doc(), {
      type: "credit_cauris", source: "manual", amount, actor_uid: adminUid,
      cauris_before: before, cauris_after: after,
      wallet_version_before: vBefore, wallet_version_after: vBefore + 1,
      details: { admin: true, reason }, timestamp: FieldValue.serverTimestamp(),
    });
    return after;
  });
  logger.info("adminAdjustCauris", { uid, amount, by: adminUid });
  return { ok: true, cauris: result };
});

/** Bannit / débannit un joueur : désactive le compte Auth + flag profil. */
export const adminSetBan = onCall(OPTS, async (req): Promise<{ ok: true; banned: boolean }> => {
  const adminUid = requireAdmin(req.auth);
  const uid = (req.data?.uid as string) || "";
  const banned = req.data?.banned === true;
  if (!uid) throw new HttpsError("invalid-argument", "uid requis.");
  if (uid === adminUid) throw new HttpsError("failed-precondition", "Tu ne peux pas te bannir toi-même.");
  try { await getAuth().updateUser(uid, { disabled: banned }); }
  catch (e) { const c = (e as { code?: string }).code; if (c !== "auth/user-not-found") throw new HttpsError("internal", (e as Error).message); }
  await getFirestore().collection("profiles").doc(uid).set(
    { banned, banned_at: banned ? FieldValue.serverTimestamp() : null, banned_by: banned ? adminUid : null }, { merge: true });
  logger.info("adminSetBan", { uid, banned, by: adminUid });
  return { ok: true, banned };
});

/** Suppression RGPD d'un joueur arbitraire (profil + users/{uid} récursif + Auth). */
export const adminDeletePlayer = onCall(OPTS, async (req): Promise<{ ok: true; uid: string }> => {
  const adminUid = requireAdmin(req.auth);
  const uid = (req.data?.uid as string) || "";
  if (!uid) throw new HttpsError("invalid-argument", "uid requis.");
  if (uid === adminUid) throw new HttpsError("failed-precondition", "Utilise la suppression de compte standard pour toi-même.");
  const db = getFirestore();
  try {
    await db.collection("profiles").doc(uid).delete();
    await db.recursiveDelete(db.collection("users").doc(uid));
  } catch (e) {
    logger.error("adminDeletePlayer: firestore purge failed", { uid, error: e });
    throw new HttpsError("internal", "Échec de la suppression des données.");
  }
  try { await getAuth().deleteUser(uid); }
  catch (e) { const c = (e as { code?: string }).code; if (c !== "auth/user-not-found") throw new HttpsError("internal", "Échec suppression Auth."); }
  logger.info("adminDeletePlayer: done", { uid, by: adminUid });
  return { ok: true, uid };
});
