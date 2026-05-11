/**
 * requestRematch — Cloud Function callable (v2).
 *
 * Flux :
 * 1. Vérifie l'auth.
 * 2. Lit /matches/{previousMatchId}/players pour confirmer que le caller
 *    était bien participant du match précédent (anti-abus).
 * 3. Rate-limit 1 rematch / 10 s par paire (uid, opponentUid) via RTDB.
 * 4. Tire une devinette serveur (même pool que requestMatch).
 * 5. Crée /matches/{newMatchId} avec target_uid=opponentUid (déclenchera
 *    sendChallengeNotif → notif FCM à l'adversaire).
 * 6. Retourne {matchId, secret} au caller.
 *
 * Le caller observe /matches/{newMatchId} (stream RTDB).
 * L'adversaire reçoit la notif → tape → deep link → joinDuel → match démarre.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getDatabase } from "firebase-admin/database";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { requireAuth } from "../utils/auth";
import { ELO_INITIAL } from "./elo";
import * as logger from "firebase-functions/logger";

// Même pool de devinettes que requestMatch — partage à terme dans un module dédié.
const SAMPLE_DEVINETTES = [
  {
    answer: "CALEBASSE",
    lettersPool: ["C", "A", "L", "E", "B", "A", "S", "S", "E"],
    riddle: "Je suis la fille du champ, la mère de la cuisine.",
    explanation:
      "La calebasse est une courge séchée utilisée comme récipient en Afrique de l'Ouest.",
    proverb: "La calebasse ne se moque pas du pot de terre cassé.",
  },
  {
    answer: "GRIOT",
    lettersPool: ["G", "R", "I", "O", "T"],
    riddle:
      "Je garde la mémoire de ton peuple dans ma gorge et mes doigts.",
    explanation:
      "Le griot est le gardien de la tradition orale en Afrique de l'Ouest.",
    proverb: "Quand un vieux meurt, une bibliothèque brûle.",
  },
  {
    answer: "BAOBAB",
    lettersPool: ["B", "A", "O", "B", "A", "B"],
    riddle: "Je suis l'arbre dont les racines pointent vers le ciel.",
    explanation:
      "Le baobab est surnommé « arbre à l'envers » car ses branches ressemblent à des racines.",
    proverb: "Le baobab ne pousse pas en un jour.",
  },
  {
    answer: "KORA",
    lettersPool: ["K", "O", "R", "A"],
    riddle: "Vingt et une cordes, une calebasse, une voix de l'âme.",
    explanation:
      "La kora est un instrument à cordes ouest-africain à 21 cordes, emblème de la musique mandé.",
    proverb: "Celui qui tient la kora tient l'histoire.",
  },
  {
    answer: "SAVANE",
    lettersPool: ["S", "A", "V", "A", "N", "E"],
    riddle:
      "Je suis la plaine d'herbes hautes où dansent les acacia et les éléphants.",
    explanation:
      "La savane africaine couvre environ 40 % du continent, entre forêts et déserts.",
    proverb:
      "L'enfant qui n'a pas voyagé pense que sa mère est la meilleure cuisinière.",
  },
];

interface RequestRematchData {
  previousMatchId: string;
  opponentUid: string;
}

interface RequestRematchResult {
  matchId: string;
  secret: string;
}

/** Génère un matchId lisible (6 caractères, pas d'ambigus). */
function _generateMatchId(): string {
  const chars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  let id = "";
  for (let i = 0; i < 6; i++) {
    id += chars[Math.floor(Math.random() * chars.length)];
  }
  return id;
}

/** Génère un secret hexadécimal 24 caractères. */
function _generateSecret(): string {
  const bytes: number[] = [];
  for (let i = 0; i < 12; i++) {
    bytes.push(Math.floor(Math.random() * 256));
  }
  return bytes.map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** Mélange un tableau (Fisher-Yates). */
function _shuffle<T>(arr: T[]): T[] {
  const copy = [...arr];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

/** Clé de rate-limit RTDB pour une paire de joueurs (canonique). */
function _rateLimitKey(uid1: string, uid2: string): string {
  // Trier les UIDs pour que la clé soit symétrique.
  const [a, b] = [uid1, uid2].sort();
  return `rematch_rate_limit/${a}_${b}`;
}

export const requestRematch = onCall<
  RequestRematchData,
  Promise<RequestRematchResult>
>(
  { region: "europe-west1" },
  async (request) => {
    const callerUid = requireAuth(request.auth);
    const { previousMatchId, opponentUid } = request.data;

    if (!previousMatchId || typeof previousMatchId !== "string") {
      throw new HttpsError("invalid-argument", "previousMatchId requis.");
    }
    if (!opponentUid || typeof opponentUid !== "string") {
      throw new HttpsError("invalid-argument", "opponentUid requis.");
    }
    if (opponentUid === callerUid) {
      throw new HttpsError(
        "invalid-argument",
        "Tu ne peux pas te défier toi-même."
      );
    }

    const rtdb = getDatabase();
    const db = getFirestore();
    const now = Date.now();

    // --- Vérifier que le caller était dans le match précédent ---
    const prevSnap = await rtdb
      .ref(`matches/${previousMatchId}/players`)
      .get();
    if (!prevSnap.exists()) {
      throw new HttpsError(
        "not-found",
        `Match précédent ${previousMatchId} introuvable.`
      );
    }
    const prevPlayers = prevSnap.val() as Record<string, unknown>;
    if (!prevPlayers[callerUid]) {
      throw new HttpsError(
        "permission-denied",
        "Tu n'étais pas participant du match précédent."
      );
    }
    if (!prevPlayers[opponentUid]) {
      throw new HttpsError(
        "permission-denied",
        "L'adversaire n'était pas dans le match précédent."
      );
    }

    // --- Rate-limit : 1 rematch / 10 s par paire ---
    const rateLimitKey = _rateLimitKey(callerUid, opponentUid);
    const rateLimitSnap = await rtdb.ref(rateLimitKey).get();
    if (rateLimitSnap.exists()) {
      const lastTs = rateLimitSnap.val() as number;
      if (now - lastTs < 10_000) {
        throw new HttpsError(
          "resource-exhausted",
          "Attends 10 secondes avant de renvoyer un défi."
        );
      }
    }

    // Écrire le timestamp de rate-limit (TTL auto nettoyé par une CF de maintenance,
    // ou simplement écrasé au prochain appel — le nœud est trop petit pour poser problème).
    await rtdb.ref(rateLimitKey).set(now);

    // --- Tirer la devinette serveur ---
    const devinette =
      SAMPLE_DEVINETTES[Math.floor(Math.random() * SAMPLE_DEVINETTES.length)];
    const shuffledLetters = _shuffle(devinette.lettersPool);

    // --- Lire l'ELO du caller pour l'enregistrer dans le match ---
    const profileSnap = await db
      .collection("profiles")
      .doc(callerUid)
      .get();
    const callerElo: number =
      (profileSnap.data()?.["elo"] as number | undefined) ?? ELO_INITIAL;

    // --- Créer le nouveau match ---
    const newMatchId = _generateMatchId();
    const secret = _generateSecret();

    const matchData: Record<string, unknown> = {
      secret,
      created_by: callerUid,
      created_at: now,
      phase: "waiting",
      answer: devinette.answer,
      letters_pool: shuffledLetters,
      riddle: devinette.riddle,
      explanation: devinette.explanation,
      proverb: devinette.proverb,
      is_ranked: true,
      // target_uid déclenche sendChallengeNotif → notif FCM à l'adversaire.
      target_uid: opponentUid,
      // Métadonnées rematch (traçabilité, analytics).
      previous_match_id: previousMatchId,
      caller_elo: callerElo,
      players: {
        [callerUid]: { progress: 0, found: false },
      },
    };

    await rtdb.ref(`matches/${newMatchId}`).set(matchData);

    logger.info(
      `[requestRematch] caller=${callerUid} vs opponent=${opponentUid} ` +
        `newMatchId=${newMatchId} previousMatchId=${previousMatchId}`
    );

    return { matchId: newMatchId, secret };
  }
);
