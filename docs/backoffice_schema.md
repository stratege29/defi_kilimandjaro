# Backoffice — Schéma Firestore & cycle de vie des packs

> **Statut** : design Phase 1 (juin 2026). À implémenter dans les Cloud Functions
> `functions/src/admin/`. Cf [plan d'implémentation backoffice](backoffice_implementation_plan.md)
> (à venir).
>
> **Contraintes héritées** :
> - [`docs/ota_v2_design.md`](ota_v2_design.md) — pas d'OTA au boot, sync manuel
> - [`docs/firebase-setup.md`](firebase-setup.md) — région `europe-west1`, claims auth
> - [`CLAUDE.md`](../CLAUDE.md) — Clean Archi stricte, anti-cheat 100% serveur

---

## 1. Objectif

Permettre l'ajout et l'édition de packs de devinettes **100% via backoffice web**,
sans release App Store / Play Store.

Cible long terme : **centaines de packs × ~500 questions** = 50 000 à 500 000 devinettes
au total, éditables granulairement par plusieurs admins en parallèle, avec historique
versions, rollback, audit log, et publication atomique vers les clients.

## 2. Principes architecturaux

1. **Firestore = source de vérité** pour le catalogue et le contenu en édition.
2. **Cloud Storage = artefacts publiés** (`.json.gz` immuables une fois uploadés).
3. **Toutes les écritures** passent par des **Cloud Functions admin** (`functions/src/admin/`).
   Les `firestore.rules` interdisent l'écriture directe par le client.
4. **Versionning par pack**, jamais global. Un pack peut être en v3 alors qu'un autre est en v1.
5. **Idempotence du publish** : le hash SHA256 doit être reproductible — pas de timestamp
   ni de champ non-déterministe dans le payload final (cf. comportement actuel du seed script).
6. **Anti-cheat** : aucune génération de contenu ni validation de purchase côté client
   (cf. CLAUDE.md règles strictes).
7. **Compat ascendante OTA v0.2** : `content_packs/<packId>` et `content_index/global`
   restent les structures lues par `ManifestSyncService` côté client. Les nouvelles
   collections `packs/`, `catalog/` sont des **structures backoffice**, jamais lues par
   l'app mobile en runtime (sauf via le RemoteCatalogRepository Phase 3).

## 3. Schéma Firestore complet

### 3.1 Collections existantes — INCHANGÉES (rétrocompat)

```
content_packs/{packId}            ← manifest courant pointé par les clients
  {
    pack: "culture_ci",
    current_version: 2,
    format_version: 3,
    hash_sha256: "...",
    size_bytes: 39168,
    count: 350,
    storage_path: "packs/v2/culture_ci/culture_ci-v2.json.gz",
    download_url: "https://firebasestorage.googleapis.com/v0/b/.../culture_ci-v2.json.gz",
    min_app_version: "0.1.0",
    langs: ["fr"],
    default_lang: "fr",
    enabled: true
  }

content_index/global              ← index plat des packs actifs (rétrocompat ManifestSyncService)
  {
    packs: ["culture_ci", "crack_nouchi", "football_ci"],
    min_format_version: 3
  }
```

### 3.2 Nouvelles collections backoffice

```
catalog/index                     ← catalogue enrichi pour l'app (Phase 3) et l'UI admin
  {
    schema_version: 4,
    catalog_version: 12,           ← bump à chaque publish, sert de cache-bust client
    packs: [
      {
        id: "culture_ci",
        visible: true,             ← masquer sans archiver
        ordering: 10,              ← tri UI
        bundled: true,             ← présent dans le starter bundle de l'app
        free_choice_eligible: true,
        unlock_cost_cauris: 0,     ← 0 = gratuit, ex 2000 sinon
        available_from: <ts|null>,
        available_until: <ts|null>,
        min_app_version: "0.1.0",
        theme_color_hex: "#FFAA00",
        icon_url: "gs://.../icons/culture_ci.png",
        tags: ["culture", "tradition"],  ← tags marketing du pack (≠ tags devinettes)
        updated_at: <ts>,
        updated_by: <uid>
      },
      ...
    ]
  }

catalog/tags_whitelist            ← whitelist des tags valides pour les devinettes
  {
    tags: ["cuisine", "tradition", "village", "joueur", "club", "stade", ...],
    updated_at: <ts>,
    updated_by: <uid>
  }
```

```
packs/{packId}/
  meta                            ← métadonnées éditables du pack (1 doc)
    {
      id: "culture_ci",
      bundled: true,               ← présent en starter
      latest_published_version: 2, ← dernière version active
      next_draft_version: 3,       ← version en cours d'édition (incrément lazy)
      pending_changes: 0,          ← compteur devinettes en draft (recalc periodique)
      created_at: <ts>,
      created_by: <uid>,
      updated_at: <ts>,
      updated_by: <uid>
    }

  i18n/{lang}                     ← name + description par langue (subcoll)
    {
      lang: "fr",
      name: "Culture CI",
      description: "Cuisine, traditions, lieux et histoire de Côte d'Ivoire",
      short_tagline: "L'âme ivoirienne en énigmes",
      updated_at: <ts>,
      updated_by: <uid>
    }

  devinettes/{deviId}             ← UNE DEVINETTE = UN DOC (subcoll)
    {
      ─ contenu (format v3 strict) ─
      id: "culture_ci_001",
      pack: "culture_ci",
      country: "ci",
      answer: "FOUTOU",
      answer_normalized: "foutou",
      letters_pool: ["F","O","U","T","O","U"],
      riddle: { fr: "...", en: "..." },
      explanation: { fr: "...", en: "..." },
      difficulty: 1,
      estimated_time_s: 25,
      tags: ["cuisine","tradition"],
      format_version: 3,

      ─ cycle de vie backoffice ─
      status: "draft" | "published" | "archived" | "deleted",
      published_version: 2,        ← version où elle est actuellement publiée (null si jamais)
      draft_version: 3,            ← version où elle a été ajoutée/modifiée en draft (null si pas de draft)
      deleted_at: null | <ts>,
      created_at: <ts>,
      created_by: <uid>,
      updated_at: <ts>,
      updated_by: <uid>
    }

  versions/{N}                    ← snapshot manifest de chaque publish (subcoll)
    {
      number: 2,
      hash_sha256: "...",
      size_bytes: 39168,
      count: 350,
      storage_path: "packs/v2/culture_ci/culture_ci-v2.json.gz",
      download_url: "...",
      langs: ["fr"],
      published_at: <ts>,
      published_by: <uid>,
      status: "active" | "archived",
      previous_version: 1
    }

  audit/{logId}                   ← journal des actions admin (subcoll)
    {
      type: "publish" | "rollback" | "upsert_devinette" | "delete_devinette" |
            "bulk_import" | "meta_update" | "i18n_update",
      actor_uid: <uid>,
      actor_email: <email>,
      timestamp: <ts>,
      details: { ... }              ← payload spécifique au type
    }
```

```
users/{uid}/inventory             ← Phase 4 (monétisation cauris-only)
  {
    cauris_balance: 1500,
    owned_packs: ["culture_ci", "football_ci"],
    free_pack_chosen: "culture_ci",
    last_unlock_at: <ts>
  }
```

### 3.3 Indexes Firestore requis

À déclarer dans `firestore.indexes.json` :

```json
{
  "indexes": [
    {
      "collectionGroup": "devinettes",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "difficulty", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "devinettes",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "id", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "devinettes",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "tags", "arrayConfig": "CONTAINS" }
      ]
    }
  ]
}
```

## 4. Cycle de vie d'une devinette

```
   [Création UI admin]
            │
            ▼
    status: "draft"
    draft_version: N+1
    published_version: null  (ou ancienne version si édition d'une publiée)
            │
            ▼
    [Bouton "Publier pack" UI]
            │
            ├──► CF validatePackDraft
            │     ├─ KO → reste en draft, errors retournées à l'UI
            │     └─ OK → continue
            ▼
    CF publishPack :
      1. Lit toutes les devinettes WHERE status IN ('draft', 'published')
      2. Filtre celles avec deleted_at != null (exclues de l'export)
      3. Sérialise en JSON v3 + gzip + SHA256
      4. Upload Storage gs://<bucket>/packs/v2/<id>/<id>-vN.json.gz
      5. Crée packs/<id>/versions/N (status=active)
      6. Archive packs/<id>/versions/N-1 (status=archived)
      7. Upsert content_packs/<id> (manifest courant)
      8. UPDATE devinettes WHERE status='draft':
           status='published', published_version=N, draft_version=null
      9. UPDATE devinettes WHERE status='archived' (soft-deleted depuis dernière publish):
           status='deleted', deleted_at=now
      10. Bump catalog/index.catalog_version
      11. Write packs/<id>/audit avec type='publish'
            │
            ▼
    status: "published"
    published_version: N
    draft_version: null
            │
       [Édition UI]
            │
            ▼
    status: "draft"
    draft_version: N+1
    published_version: N  (conservée tant que pas publish)
            │
            ▼
        ... cycle ...

   [Suppression UI]
            │
            ▼
    Si jamais publiée   → DELETE doc (hard delete, pas d'historique)
    Si déjà publiée     → status='archived', deleted_at=now
                          (au prochain publish: passe à 'deleted', exclue de l'export)
```

## 5. Cycle de vie d'une version de pack

```
versions/{N}.status :
  ───────────────────────────────────────
  N créé par publishPack    → "active"
  N+1 publié par publishPack  → "active"   (N passe automatiquement à "archived")
  Rollback vers N            → "active"   (N+1 repasse à "archived")
  ───────────────────────────────────────

Une seule version par pack peut être "active" à la fois.
Storage : les .json.gz archivés sont conservés (pas de delete) pour permettre rollback.
TTL Storage : lifecycle policy GCS → archive class après 90 jours, delete après 1 an
  (à configurer manuellement dans la console GCS, hors scope code).
```

## 6. Règles Firestore — sécurité

```
match /databases/{db}/documents {

  // === Catalog (lecture publique pour l'app, écriture CF only) ===
  match /catalog/{docId} {
    allow read: if true;
    allow write: if false;  // CFs admin uniquement (admin SDK bypass)
  }

  match /content_packs/{packId} {
    allow read: if true;
    allow write: if false;
  }

  match /content_index/{docId} {
    allow read: if true;
    allow write: if false;
  }

  // === Packs (backoffice) ===
  match /packs/{packId} {
    allow read:  if isAdmin() || isEditor() || isModerator();
    allow write: if false;
  }
  match /packs/{packId}/meta {
    allow read:  if isAdmin() || isEditor() || isModerator();
    allow write: if false;
  }
  match /packs/{packId}/i18n/{lang} {
    allow read:  if isAdmin() || isEditor();
    allow write: if false;
  }
  match /packs/{packId}/devinettes/{deviId} {
    allow read:  if isAdmin() || isEditor();
    allow write: if false;
  }
  match /packs/{packId}/versions/{n} {
    allow read:  if isAdmin() || isEditor();
    allow write: if false;
  }
  match /packs/{packId}/audit/{logId} {
    allow read:  if isAdmin();   // audit log admin-only (RGPD-friendly)
    allow write: if false;
  }

  // === Users inventory ===
  match /users/{uid}/inventory {
    allow read:  if request.auth.uid == uid || isAdmin();
    allow write: if false;  // CFs unlockPack + validateCaurisPurchase
  }

  // === Helpers ===
  function isAdmin() {
    return request.auth != null
        && request.auth.token.role == "admin";
  }
  function isEditor() {
    return request.auth != null
        && (request.auth.token.role == "editor"
            || request.auth.token.role == "admin");
  }
  function isModerator() {
    return request.auth != null
        && (request.auth.token.role == "moderator"
            || request.auth.token.role == "admin");
  }
}
```

### Rôles & permissions matrix

| Rôle | catalog/* | packs/* (lecture) | devinettes (edit) | i18n (edit) | publishPack | rollbackPack | audit | submissions modération |
|---|---|---|---|---|---|---|---|---|
| **admin** | R | R | via CF | via CF | ✓ | ✓ | R | ✓ |
| **editor** | R | R | via CF | via CF | ✗ | ✗ | ✗ | ✗ |
| **moderator** | R | R (meta seulement) | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| **user** | R | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |

## 7. Schéma Storage

```
gs://<bucket>/
  packs/v2/<packId>/
    <packId>-v1.json.gz           ← archivé, conservé pour rollback
    <packId>-v2.json.gz           ← actif (pointé par content_packs/<id>)
    <packId>-v3.json.gz           ← prochaine version au publish

  assets/icons/<packId>.png       ← icône du pack (uploadée via UI admin)
  assets/icons/<packId>-128.png   ← versions resized (CF de redim post-upload, Phase 4 polish)

  drafts/                         ← (optionnel, Phase 4) backups JSON bruts éditeur
    <packId>/<sessionId>.json
```

## 8. Validation strict (CF validatePackDraft)

Règles appliquées en bloc avant tout publish :

| Règle | Détail | Si violée |
|---|---|---|
| **Format v3** | tous les champs obligatoires présents (cf §3.2 devinettes) | reject |
| **answer** | 4 ≤ len ≤ 12, A-Z + tolérance accents listés (ï, é, à) | reject |
| **answer_normalized** | === `normalize(answer)` (NFD + lowercase) | reject |
| **letters_pool** | === lettres de `answer` (multiset) | reject |
| **riddle.fr** | non vide, ne contient PAS la réponse (case-insensitive) | reject |
| **explanation.fr** | non vide | warn (publish OK) |
| **tags** | tous dans `catalog/tags_whitelist.tags` | reject |
| **difficulty** | ∈ {1, 2, 3, 4} | reject |
| **estimated_time_s** | 10 ≤ n ≤ 120 | warn |
| **id** | match `^<packId>_\d{3,4}$`, unique au sein du pack | reject |
| **doublons answer** | aucune autre devinette du pack n'a la même `answer` | reject |
| **format_version** | === 3 | reject |
| **deleted_at** | si `status == 'draft'`, doit être `null` | reject |

Output CF :
```typescript
{
  valid: boolean,
  total: number,
  errors: Array<{ deviId: string, code: string, message: string }>,
  warnings: Array<{ deviId: string, code: string, message: string }>
}
```

## 9. Migration depuis l'existant (one-shot)

Une fois Phase 1 livrée, il faut migrer :

1. **Catalogue actuel** (`assets/data/devinettes/starter/_index.json` + `_index.json` racine)
   → script `tools/scripts/migrate_catalog_to_firestore.mjs` qui écrit `catalog/index`
2. **Tags whitelist** (extraite du contenu existant + tags football Gemini)
   → écriture `catalog/tags_whitelist`
3. **Métadonnées packs** (i18n actuellement dans `easy_localization`)
   → script qui écrit `packs/<id>/i18n/{fr,en}` à partir de `assets/data/i18n/{fr,en}.json`
4. **Devinettes existantes** (starter `culture_ci`, `crack_nouchi`, + OTA `culture_ci`, `football_ci`)
   → script qui écrit `packs/<id>/devinettes/{deviId}` avec `status='published'`,
     `published_version` = version actuelle de `content_packs/<id>`

Ces migrations sont **one-shot** : après, tout passe par les CFs admin. Le starter
JSON reste dans le repo pour le first-launch offline (cf décisions actées), mais n'est
plus modifié à la main.

## 10. Conventions de naming Cloud Functions

Toutes les CFs admin vivent dans `functions/src/admin/` et sont exportées **sans préfixe**
dans `index.ts` (cohérent avec la convention existante du projet — pas de namespace).

Par convention, on les nomme avec un verbe métier explicite :
- `validatePackDraft`, `publishPack`, `rollbackPack`
- `upsertDevinette`, `deleteDevinette`, `bulkImportDevinettes`
- `upsertPackMeta`, `upsertPackI18n`
- `upsertCatalogEntry`, `upsertTagsWhitelist`
- `setUserRole` (claim management — admin only)

Toutes en `europe-west1`, `onCall` (HTTPS callable), guards via `requireAdmin()` ou
`requireEditor()` (helpers à ajouter dans `functions/src/utils/auth.ts`).

## 11. Considérations performance & coût

| Opération | Volume estimé | Coût Firestore |
|---|---|---|
| Ouvrir éditeur d'un pack (500 Q) | 500 reads | ~3 × 10⁻⁵ € / ouverture |
| Sauvegarder 1 devinette | 1 write + 1 audit write | ~9 × 10⁻⁶ € |
| Publish (500 Q) | 500 reads + 500 updates + 5 metadata writes | ~3 × 10⁻⁴ € |
| Bulk import 500 Q | 500 writes (batched) | ~9 × 10⁻⁴ € |
| Sync client (lecture catalog) | 1 read | ~3 × 10⁻⁷ € |

À l'échelle cible (100 packs × 500 Q × 100 admins × 10 ops/jour) : **<10 € / mois**
Firestore + Storage. Très en deçà du free tier pour la majorité des opérations.

## 12. Roadmap d'implémentation

| Phase | Sprint | Livrable |
|---|---|---|
| **1. CFs admin** | 1 sem | validatePackDraft, publishPack, rollbackPack, upsertDevinette, bulkImportDevinettes, setUserRole + rules + tests |
| **2. UI backoffice** | 2 sem | écrans Catalog, PackEditor, DevinetteEditor, PublishDialog dans `tools/admin_console/` |
| **3. Catalogue distant app** | 1 sem | `RemoteCatalogRepository`, fallback bundle, release app (1×) |
| **4. Monétisation cauris** | 1 sem | IAP cauris, CF unlockPack, ShopView refondu (release groupée Phase 3) |
| **5. Polish** | 1 sem | UI rollback, preview live, audit log, stats |

Total : ~6 semaines après doc validée.

## 13. Open questions

- **Recherche full-text dans les devinettes** : pour 50 000+ Q, Firestore ne suffit pas.
  Option : sync vers Algolia (5-10 €/mois) ou Typesense (self-hosted). À décider en Phase 5.
- **Multi-langues** : actuellement riddle/explanation supportent `{fr, en}`. Si on ajoute
  d'autres langues (yoruba, mandinka...), le schéma supporte déjà mais il faut décider
  d'une langue de référence (fr = source de vérité, autres = traductions).
- **Workflow editorial** : faut-il un état `review` entre `draft` et `published` (validation
  par un admin différent de l'éditeur) ? Pas dans v1, à voir en Phase 5.
- **Versionning des i18n du pack** : si on change le nom d'un pack en prod, faut-il une
  v2 ? Aujourd'hui non : l'i18n est un doc Firestore mutable, le client le re-lit au boot.

---

**Auteur** : Claude + Arnaud, juin 2026
**Statut** : draft v1 — à valider avant d'attaquer les CFs Phase 1
