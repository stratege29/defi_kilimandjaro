/**
 * requestMatch — Cloud Function callable (v2).
 *
 * Flux :
 * 1. Vérifie l'auth.
 * 2. Lit (ou initialise à 1000) l'ELO du joueur dans Firestore.
 * 3. Cherche dans /lobby un adversaire dans la bande ELO ±band_radius.
 *    - band_radius initial = 150 m, expansé par le client via expansion_step.
 * 4a. Si adversaire trouvé :
 *     - Tire une devinette dans village_des_or (TODO: étendre avec d'autres packs).
 *     - Crée /matches/{matchId} avec is_ranked=true.
 *     - Supprime les 2 entrées lobby.
 *     - Retourne {status:"matched", matchId, matchData}.
 * 4b. Sinon : écrit/met à jour /lobby/{uid} et retourne {status:"waiting"}.
 *
 * Rate-limit : 1 appel / 3 s par UID (vérifié via Realtime DB timestamp).
 * Le client doit rappeler toutes les 5 s avec un expansion_step croissant.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getDatabase } from "firebase-admin/database";
import { requireAuth } from "../utils/auth";
import { ELO_INITIAL } from "./elo";

// Devinettes disponibles pour le matchmaking — MVP pack village_des_or.
// TODO(phase-7): charger dynamiquement depuis Firestore community_packs.
const SAMPLE_DEVINETTES = [
  {
    answer: "CALEBASSE",
    lettersPool: ["C", "A", "L", "E", "B", "A", "S", "S", "E"],
    riddle: "Je suis la fille du champ, la mère de la cuisine.",
    explanation:
      "La calebasse est une courge séchée utilisée comme récipient en Afrique de l'Ouest.",
    proverb:
      "La calebasse ne se moque pas du pot de terre cassé.",
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
    proverb: "L'enfant qui n'a pas voyagé pense que sa mère est la meilleure cuisinière.",
  },
];

interface RequestMatchData {
  request_id: string;
  expansion_step?: number; // 0=±150, 1=±225, 2=±300 …
}

interface RequestMatchResult {
  status: "matched" | "waiting";
  matchId?: string;
  matchData?: Record<string, unknown>;
  lobbyEntry?: Record<string, unknown>;
}

export const requestMatch = onCall<RequestMatchData, Promise<RequestMatchResult>>(
  { region: "europe-west1" },
  async (request) => {
    const uid = requireAuth(request.auth);
    const { request_id, expansion_step = 0 } = request.data;

    if (!request_id || typeof request_id !== "string") {
      throw new HttpsError("invalid-argument", "request_id requis.");
    }

    const db = getFirestore();
    const rtdb = getDatabase();
    const now = Date.now();

    // --- Rate limit : 1 appel / 3 s ---
    const lobbyRef = rtdb.ref(`lobby/${uid}`);
    const existingSnap = await lobbyRef.get();
    if (existingSnap.exists()) {
      const existing = existingSnap.val() as {
        ts: number;
        request_id: string;
        matched_to?: string;
      };
      const elapsedMs = now - (existing.ts ?? 0);
      // Si même request_id, c'est une expansion — pas de rate limit.
      if (existing.request_id !== request_id && elapsedMs < 3000) {
        throw new HttpsError(
          "resource-exhausted",
          "Trop de requêtes. Attends 3 secondes entre chaque tentative."
        );
      }
      // Si déjà matché, retourner le matchId.
      if (existing.matched_to) {
        return { status: "waiting", lobbyEntry: { matched_to: existing.matched_to } };
      }
    }

    // --- Lire ELO depuis Firestore (init à 1000 si absent) ---
    const profileRef = db.collection("profiles").doc(uid);
    const profileSnap = await profileRef.get();
    let myElo: number;

    if (!profileSnap.exists) {
      myElo = ELO_INITIAL;
      // Initialiser le profil via Admin SDK (pas depuis le client).
      await profileRef.set(
        {
          elo: ELO_INITIAL,
          peakElo: ELO_INITIAL,
          totalDuels: 0,
          wins: 0,
          losses: 0,
          createdAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } else {
      const data = profileSnap.data()!;
      myElo = (data["elo"] as number) ?? ELO_INITIAL;
    }

    // --- Calculer la bande ELO ---
    // expansion_step 0 → ±150, 1 → ±225, 2 → ±300, …
    const bandRadius = 150 + expansion_step * 75;
    const eloMin = myElo - bandRadius;
    const eloMax = myElo + bandRadius;

    // --- Scanner le lobby ---
    const lobbySnap = await rtdb.ref("lobby").get();
    let opponentUid: string | null = null;
    let opponentElo: number = ELO_INITIAL;

    if (lobbySnap.exists()) {
      const lobbyData = lobbySnap.val() as Record<
        string,
        { mmr: number; ts: number; request_id: string; matched_to?: string }
      >;
      for (const [candidateUid, entry] of Object.entries(lobbyData)) {
        // Exclure soi-même, les déjà matchés, et ceux hors bande.
        if (candidateUid === uid) continue;
        if (entry.matched_to) continue;
        if (entry.mmr < eloMin || entry.mmr > eloMax) continue;
        // Prendre le premier candidat valide.
        opponentUid = candidateUid;
        opponentElo = entry.mmr;
        break;
      }
    }

    // --- Match trouvé ---
    if (opponentUid) {
      const matchId = _generateMatchId();
      const devinette =
        SAMPLE_DEVINETTES[Math.floor(Math.random() * SAMPLE_DEVINETTES.length)];
      const shuffled = _shuffle(devinette.lettersPool);

      const matchData: Record<string, unknown> = {
        created_by: uid,
        created_at: now,
        phase: "waiting",
        answer: devinette.answer,
        letters_pool: shuffled,
        riddle: devinette.riddle,
        explanation: devinette.explanation,
        proverb: devinette.proverb,
        is_ranked: true,
        players: {
          [uid]: { progress: 0, found: false },
          [opponentUid]: { progress: 0, found: false },
        },
      };

      // Écriture atomique dans Realtime DB.
      const updates: Record<string, unknown> = {
        [`matches/${matchId}`]: matchData,
        [`lobby/${uid}`]: null,
        [`lobby/${opponentUid}`]: null,
      };
      await rtdb.ref().update(updates);

      return {
        status: "matched",
        matchId,
        matchData,
      };
    }

    // --- Pas d'adversaire : écrire / mettre à jour le lobby ---
    await lobbyRef.set({
      mmr: myElo,
      ts: now,
      request_id,
    });

    return {
      status: "waiting",
      lobbyEntry: { mmr: myElo, ts: now },
    };
  }
);

function _generateMatchId(): string {
  const chars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  let id = "";
  for (let i = 0; i < 6; i++) {
    id += chars[Math.floor(Math.random() * chars.length)];
  }
  return id;
}

function _shuffle<T>(arr: T[]): T[] {
  const copy = [...arr];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}
