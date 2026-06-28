# Pack Creator — pipeline de contenu automatisé

Pipeline IA piloté depuis la console admin (`tools/admin_console_web`, onglet
**Pack Creator**) pour produire des packs de devinettes : recherche + génération
sourcée, revue humaine, publication, puis ré-approvisionnement hebdomadaire.

## Flux

1. **Nouveau pack** (`createPackJob`) — on enfile `{packId, topic, targetTotal}`.
   Le pack est ajouté caché (`visible:false`) à `catalog/index.packs[]`.
2. **Plan de recherche** (`generateResearchPlan`) — Claude propose sous-thèmes +
   répartition par niveau de difficulté (1–4). Statut `plan_review`.
3. **Validation du plan** (`approveResearchPlan`) — éditable dans la console.
   Statut `plan_approved`.
4. **Génération** — le cron `drainPackJobs` (toutes les 2 min) traite **1 lot de
   25 questions** par tick : génération structurée (quota par niveau + dédup) →
   checks mécaniques serveur → vérification/sourcing via recherche web. Les
   candidats atterrissent en **staging** `pack_jobs/{jobId}/candidates`.
   Statut `generating` → `review` quand tous les lots sont faits.
5. **Revue** — chaque question est éditable / approuvable / rejetable. Approuver
   copie le candidat dans `packs/{packId}/devinettes` (status `draft`,
   `letters_pool`/`answer_normalized` recalculés).
   - **Réaffectation** (`reassignCandidate`) : une question EN ATTENTE peut être
     déplacée vers un autre pack (`effectivePackId`) — elle reste `pending` et
     apparaît dans la revue de ce pack. Tant qu'elle n'est pas approuvée, elle
     n'entre dans AUCUN draft → republier le pack cible ne la pousse pas.
   - **Vue « En attente par pack »** (onglet) : agrège via `collectionGroup` les
     candidats de tous les jobs destinés à un pack donné (filtre statut).
6. **Publication** — bouton « Publier le pack » → `publishPack` existant
   (versioning + OTA + mirroir pool duel inchangés).
7. **Ré-appro hebdo** — `setPackTopup` active `pack_topup/{packId}` ; le cron
   `weeklyPackTopup` (lundi 06:00 Abidjan) enfile un job `phase=topup` de
   `perWeek` questions (10 par défaut) en revue, dédupliquées.

## Modèle Firestore

- `pack_jobs/{jobId}` — état (`status`, `plan`, `progress`, `caps`, `usage`).
- `pack_jobs/{jobId}/candidates/{candId}` — questions générées (staging).
- `pack_jobs/{jobId}/batches/{batchIndex}` — registre d'idempotence des lots.
- `pack_topup/{packId}` — config du ré-appro hebdo.

Règles : lecture `isEditor()`, écritures serveur uniquement (CFs).

## IA — stack « quasi gratuit » (par défaut)

Abstraction provider `functions/src/ai/provider.ts` (param `PACK_AI_ENGINE`,
défaut `gemini`).

- **Génération + plan** : **Google Gemini 2.5 Flash** (free tier), sortie
  structurée (`responseSchema`). `functions/src/ai/geminiClient.ts`.
- **Vérification / sourcing** : **hybride Wikipedia (FR) → grounding** :
  résumé fr.wikipedia confronté par Gemini (source = URL Wikipedia), repli
  Google Search grounding pour les candidats sans source. `ai/wikiVerify.ts`.
  → coût ≈ $0 dans les quotas free tier ; le cron lent (1 lot/2 min) y reste.
- **Moteur premium optionnel** : Claude Opus 4.8 (`ai/claudeClient.ts`) en
  posant `PACK_AI_ENGINE=claude` + en ajoutant `ANTHROPIC_API_KEY` à `AI_SECRETS`.
- Garde-fous : caps par job (`maxClaudeCallsPerJob`, `maxUsd`, `maxCandidates`),
  circuit breaker (`consecutiveErrors >= 5` → `failed`), usage tokens tracé
  (`estUsd` = tarifs Flash, ≈ 0 sur free tier).
- **Quota free tier** : les 429 / `RESOURCE_EXHAUSTED` sont des erreurs *douces*
  (pas de circuit breaker, le lot repasse en `pending`, reprise auto quand le
  quota se libère). Free tier Gemini = **20 req/jour** par modèle.
- **Mode éco quota** (`ecoQuota` à la création) : lots de **50** + vérification
  **Wikipedia uniquement** (0 appel Gemini en vérif) → ~11 appels pour 500
  questions, tient dans 20/jour. Les questions arrivent en `uncertain`
  (validation humaine en revue, source Wikipedia attachée si trouvée).

## Setup manuel (console / CLI) — à faire avant usage

1. **Secret Gemini** (région europe-west1) — clé AI Studio :
   ```sh
   firebase functions:secrets:set GEMINI_API_KEY
   ```
   Attaché (via `AI_SECRETS`) aux fonctions `generateResearchPlan` et
   `drainPackJobs`. Pour le moteur premium Claude : ajouter aussi
   `ANTHROPIC_API_KEY` et `PACK_AI_ENGINE=claude`.
2. **Déploiement** :
   ```sh
   cd functions && npm run build
   firebase deploy --only functions:createPackJob,functions:cancelPackJob,functions:retryPackJob,functions:generateResearchPlan,functions:approveResearchPlan,functions:approveCandidate,functions:rejectCandidate,functions:updateCandidate,functions:setPackTopup,functions:drainPackJobs,functions:weeklyPackTopup
   firebase deploy --only firestore:rules,firestore:indexes
   ```
   (l'index `collectionGroup` sur `candidates` est requis pour la vue « par pack ».)
   (Le cron `drainPackJobs` ne consomme l'API que s'il y a un job actif.)
3. **Console admin** : `cd tools/admin_console_web && npm run build` puis
   `firebase deploy --only hosting` (site `kilimandjaro-admin-dev`).
4. **Tags whitelist** (optionnel) : `catalog/tags_whitelist.tags` (array) — si
   présent, la génération s'y restreint et la validation publishPack la fait
   respecter.
