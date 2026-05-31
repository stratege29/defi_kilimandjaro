# Go-live Production — Kilimandjaro Sagesse Ivoirienne

> Guide step-by-step pour reproduire sur `kilimandjaro-prod` ce qui est
> actuellement en place sur `kilimandjaro-dev` après Phases 1+2+3+4.
>
> **Audience** : toi (Arnaud), un futur dev qui reprend le projet, ou Claude
> en session future. Suis-le séquentiellement, **sans skip**.
>
> **Durée estimée** : 1h30-2h en suivant ce guide (sans imprévu).

---

## 0. Inventaire de ce qui doit aller en prod

| Composant | Localisation source | Action prod |
|---|---|---|
| Firestore rules | [`firestore.rules`](../firestore.rules) | `firebase deploy --only firestore:rules` |
| Firestore indexes | [`firestore.indexes.json`](../firestore.indexes.json) | `firebase deploy --only firestore:indexes` |
| **5 CFs backoffice admin** | [`functions/src/admin/`](../functions/src/admin/) | `firebase deploy --only functions:validatePackDraft,publishPack,rollbackPack,upsertDevinette,bulkImportDevinettes` |
| **4 CFs wallet serveur** | [`functions/src/wallet/`](../functions/src/wallet/) | `firebase deploy --only functions:bootstrapWallet,unlockPack,creditCauris,syncWallet` |
| Seed catalog/index + packs | [`tools/scripts/seed_backoffice.mjs`](../tools/scripts/seed_backoffice.mjs) | `node ... --project kilimandjaro-prod` |
| Claim admin pour toi | one-shot Admin SDK | script Node ponctuel |
| Storage rules (`packs/v2/**` public) | [`storage.rules`](../storage.rules) | `firebase deploy --only storage` |
| Remote Config (12 clés eco_*/ads_*) | console Firebase | manuel (cf [`remote_config_keys.md`](memory/remote_config_keys.md)) |
| Admin console hosting | [`tools/admin_console/`](../tools/admin_console/) | `firebase deploy --only hosting --project kilimandjaro-prod` (optionnel) |
| App mobile release | [`pubspec.yaml`](../pubspec.yaml) | bumper version + `flutter build` + upload stores |

---

## 1. Pré-requis (à faire UNE FOIS avant tout deploy prod)

### 1.1 Comptes & permissions

- [ ] Confirmer que ton compte (`kossea@ultimesgriots.com` ou autre) a le rôle
      **Owner** ou **Editor** sur `kilimandjaro-prod` côté GCP IAM
- [ ] Confirmer accès au projet via : `firebase projects:list` → `kilimandjaro-prod`
      doit apparaître
- [ ] Si pas listé : Firebase Console → Project Settings → Users and permissions → Add member

### 1.2 Auth CLI

```bash
firebase login --reauth
firebase use kilimandjaro-prod  # bascule le projet actif (vérif avant chaque deploy !)
gcloud auth login
gcloud config set project kilimandjaro-prod
gcloud auth application-default login   # pour les scripts Node admin SDK
```

### 1.3 Service account pour les scripts

Génère un service account JSON pour `seed_backoffice.mjs` et le set-admin-claim :

1. Firebase Console → kilimandjaro-prod → Project Settings → Service accounts
2. Generate new private key → télécharge le JSON
3. **Stocke-le hors du repo** (ex: `~/Downloads/kilimandjaro-prod-firebase-adminsdk-*.json`)
4. `.gitignore` exclut déjà `service-account*.json` — vérifie quand même

### 1.4 Firebase Auth providers

Côté Firebase Console → kilimandjaro-prod → Authentication → Sign-in method :

- [ ] **Google** : enabled (pour l'admin console + sign-in app)
- [ ] **Anonymous** : enabled (pour l'app mobile first-launch)
- [ ] **Authorized domains** : ajouter ton domaine d'hosting si différent de défaut
      (ex: `admin.kilimandjaro.app`)

### 1.5 Plan Firebase

- [ ] Confirmer que `kilimandjaro-prod` est en plan **Blaze** (pay-as-you-go) —
      Cloud Functions v2 + Storage outbound nécessitent Blaze. Si encore en
      Spark, upgrade en console.

---

## 2. Deploy infrastructure (Firestore + Storage + Functions)

### 2.1 Firestore rules + indexes

```bash
firebase deploy --only firestore:rules,firestore:indexes --project kilimandjaro-prod
```

**Vérification** : Firebase Console → Firestore → Rules → onglet "Rules history"
doit afficher le nouveau déploiement avec le contenu de `firestore.rules` actuel.

**Indexes** : Firestore Console → Indexes → vérifier qu'ils sont "Building"
puis "Enabled" (peut prendre 1-5 min).

### 2.2 Storage rules

```bash
firebase deploy --only storage --project kilimandjaro-prod
```

**Important** : les packs OTA `.json.gz` doivent être **lisibles publiquement**
(`packs/v2/**` allow read true). Sinon le client ne peut pas les télécharger.

### 2.3 Cloud Functions (build + deploy)

```bash
cd functions
npm install              # si first deploy
npm run build            # vérifier 0 erreur TS

# Deploy toutes les CFs admin + wallet
firebase deploy --only \
  "functions:validatePackDraft,functions:publishPack,functions:rollbackPack,functions:upsertDevinette,functions:bulkImportDevinettes,functions:bootstrapWallet,functions:unlockPack,functions:creditCauris,functions:syncWallet" \
  --project kilimandjaro-prod
```

Pour deploy **TOUTES** les fonctions (incluant matchmaking/iap/curation existantes) :

```bash
firebase deploy --only functions --project kilimandjaro-prod
```

**Durée** : ~3-5 min selon les fonctions à créer.

**Vérification** : Firebase Console → Functions → vérifier les **9 nouvelles** :
- `validatePackDraft`, `publishPack`, `rollbackPack`, `upsertDevinette`, `bulkImportDevinettes` (Phase 1-2)
- `bootstrapWallet`, `unlockPack`, `creditCauris`, `syncWallet` (Phase 4)
- Toutes en région `europe-west1`

---

## 3. Seed Firestore (catalog/index + tags + packs)

### 3.1 Vérifier le contenu local avant push

```bash
cd /Users/arnaudkossea/development/defi_kilimandjaro

# Quels packs sont dans le bundle starter ?
cat assets/data/devinettes/starter/_index.json

# Y a-t-il du contenu OTA additionnel à pousser ?
ls -la content/ota_packs/
```

Si tu veux ajouter du contenu OTA (ex: les 280 culture_ci + 500 football_ci générés
via Gemini), assure-toi qu'ils sont bien commit dans `content/ota_packs/`.

### 3.2 Dry-run

```bash
GOOGLE_APPLICATION_CREDENTIALS=~/Downloads/kilimandjaro-prod-firebase-adminsdk-*.json \
  node tools/scripts/seed_backoffice.mjs --project kilimandjaro-prod --dry-run
```

Vérifie :
- Le nombre de packs détectés
- Le compteur total de devinettes
- Les tags whitelistés (ne doit pas être 0)
- Les langues détectées (fr + en si applicable)

### 3.3 Seed réel

```bash
GOOGLE_APPLICATION_CREDENTIALS=~/Downloads/kilimandjaro-prod-firebase-adminsdk-*.json \
  node tools/scripts/seed_backoffice.mjs --project kilimandjaro-prod
```

**Durée** : ~30-60 sec selon le volume (Firestore batches 400/batch).

**Vérification** :
- Firebase Console → Firestore → `catalog/index` doc existe avec `schema_version: 4`
- `catalog/tags_whitelist` doc existe avec liste tags non vide
- `packs/culture_ci/meta/doc` existe (+ `packs/crack_nouchi`, etc.)
- `packs/culture_ci/devinettes/` collection contient le nombre attendu de docs

### 3.4 (Optionnel) Upload manuel des `.json.gz` OTA legacy

Si tu utilises encore le pipeline OTA legacy (`content_packs/{packId}` lu par
`ManifestSyncService`), il faut aussi :

```bash
# Build les .gz
dart run tool/seed_content_packs.dart

# Upload Storage
gsutil -m cp -r build/seed_packs/*/*.json.gz \
  gs://kilimandjaro-prod.firebasestorage.app/packs/v2/

# Upsert Firestore manifest content_packs/<id>
GOOGLE_APPLICATION_CREDENTIALS=~/Downloads/kilimandjaro-prod-firebase-adminsdk-*.json \
  node tools/scripts/seed_firestore_packs.mjs \
  --project kilimandjaro-prod \
  --bucket kilimandjaro-prod.firebasestorage.app
```

⚠️ **Note** : Phase 3 a fait que l'app lit désormais `catalog/index` en priorité.
Le pipeline OTA legacy reste utile uniquement pour les manifests devinettes
(téléchargement des packs `.gz` complets). Les métadonnées (visible, ordering,
prix) viennent de `catalog/index`.

---

## 4. Setter le claim admin sur ton compte

Sans claim `role=admin`, tu ne peux pas appeler `publishPack`, `rollbackPack`
(et toute CF guard par `requireAdmin`).

### 4.1 Identifier l'UID de ton compte prod

Le compte doit s'être connecté **au moins une fois** à l'admin console prod
(pour qu'il existe dans Firebase Auth).

```bash
# Script one-shot pour lister + setter le claim
cat > /tmp/grant_admin.mjs << 'EOF'
import admin from 'firebase-admin';
admin.initializeApp();
const email = process.argv[2];
if (!email) { console.error('usage: node grant_admin.mjs <email>'); process.exit(1); }
const user = await admin.auth().getUserByEmail(email);
console.log(`Found user: uid=${user.uid} current claims=${JSON.stringify(user.customClaims || {})}`);
await admin.auth().setCustomUserClaims(user.uid, { role: 'admin' });
console.log('✓ admin claim set. Le user doit se déconnecter + reconnecter pour rafraîchir son token.');
process.exit(0);
EOF

# Copie dans tools/scripts (qui a firebase-admin installé)
cp /tmp/grant_admin.mjs tools/scripts/grant_admin.mjs

# Lance
GOOGLE_APPLICATION_CREDENTIALS=~/Downloads/kilimandjaro-prod-firebase-adminsdk-*.json \
  node tools/scripts/grant_admin.mjs kossea@ultimesgriots.com

# Nettoie après
rm tools/scripts/grant_admin.mjs /tmp/grant_admin.mjs
```

### 4.2 Vérifier

- Connexion à l'admin console prod avec le compte → onglet Catalogue doit
  charger sans "Accès refusé"
- Bouton "Publier" sur un pack → ne doit pas retourner `permission-denied`

### 4.3 Autres rôles (editor, moderator)

Adapter le script avec `{ role: 'editor' }` ou `{ role: 'moderator' }` pour
donner des droits restreints à un membre de l'équipe (ex: un curateur qui peut
éditer mais pas publier).

---

## 5. Remote Config (12 clés économie)

Phase 4 monétisation cauris-only utilise 12 paramètres Remote Config.
Cf [`memory/remote_config_keys.md`](memory/remote_config_keys.md) pour la liste
complète. Synthèse :

| Clé | Type | Défaut | Tuning |
|---|---|---|---|
| `eco_hint_cost` | int | 20 | Coût 1er indice |
| `eco_hint_cost_multiplier` | float | 1.5 | Escalade indices |
| `eco_win_reward_base` | int | 30 | Récompense victoire |
| `eco_speed_bonus_per_second` | int | 2 | Bonus par sec restante |
| `eco_rewarded_video_bonus` | int | 50 | Cauris par pub |
| `eco_rewarded_double_enabled` | bool | true | Bouton "doubler" post-victoire |
| `eco_rewarded_daily_cap` | int | 5 | Max pubs/jour |
| `eco_initial_cauris` | int | 120 | Solde new player |
| `eco_streak_rewards` | string (CSV) | `10,20,40,60,100,150,300` | Bonus ouverture/jour |
| `ads_interstitial_every_n_levels` | int | 3 | Fréquence inter |
| `ads_interstitial_min_interval_seconds` | int | 60 | Gap min entre inter |
| `ads_killswitch` | bool | false | Coupe ALL ads |

**Création manuelle** :
- Firebase Console → kilimandjaro-prod → Remote Config → Add parameter
- Pour chaque clé : nom + type + default value
- Publier les changements (bouton en haut à droite)

Alternative : déployer le template via `firebase deploy --only remoteconfig`
(le fichier `remoteconfig.template.json` doit être à jour).

---

## 6. Vérifications post-deploy (smoke tests)

### 6.1 Functions

```bash
# Vérifier que les CFs sont bien up
curl -X POST "https://europe-west1-kilimandjaro-prod.cloudfunctions.net/syncWallet" \
  -H "Content-Type: application/json" \
  -d '{"data":{}}'
# Doit retourner 401 "unauthenticated" (pas d'auth header) — preuve que la CF est live
```

### 6.2 Firestore

```bash
# Lecture publique catalog/index
curl "https://firestore.googleapis.com/v1/projects/kilimandjaro-prod/databases/(default)/documents/catalog/index"
# Doit retourner le JSON du catalog (publique)
```

### 6.3 Admin console

1. `cd tools/admin_console`
2. Régénérer `firebase_options.dart` pour pointer sur prod :
   ```bash
   firebase apps:sdkconfig WEB <app-id-prod> --project kilimandjaro-prod
   # → écrire le résultat dans lib/firebase_options.dart
   ```
3. `flutter run -d chrome --web-port=4280 --web-header "Cross-Origin-Opener-Policy=same-origin-allow-popups" --web-header "Cross-Origin-Embedder-Policy=unsafe-none"`
4. Sign-in → vérifier catalog s'affiche → cliquer un pack → vérifier les 3 onglets

### 6.4 App mobile en mode debug pointant sur prod

Temporairement modifier `lib/firebase_options.dart` pour pointer sur prod (ou
utiliser un flavor `prod` si configuré), puis `flutter run`. Tester :

- [ ] First-launch → onboarding pack_chooser fonctionne
- [ ] MyPacks → SYNC button → catalog remote chargé
- [ ] Click "Débloquer (X ♦)" sur un pack non-owned → dialog → débit → pack apparaît
- [ ] Vérifier Firestore Console : `users/{uid}/inventory/wallet` créé + `inventory_audit` peuplé

---

## 7. Release app mobile (App Store + Play Store)

### 7.1 Bumper la version

```bash
# Édite pubspec.yaml ligne version: 0.1.0+14 → 0.1.0+15 (ou 0.2.0+1 pour mineur)
# Commit la modification
git add pubspec.yaml
git commit -m "chore(version): bump 0.1.0+14 → 0.1.0+15 (release Phase 4 wallet serveur)"
```

### 7.2 Build iOS

```bash
flutter build ios --release --dart-define-from-file=.env.prod
cd ios && pod install && cd ..
# Open ios/Runner.xcworkspace dans Xcode
# Product → Archive → Distribute App → App Store Connect
```

### 7.3 Build Android

```bash
flutter build appbundle --release --dart-define-from-file=.env.prod
# Output : build/app/outputs/bundle/release/app-release.aab
# Upload manuel sur Play Console → Internal Testing track d'abord
```

### 7.4 Checklist release

- [ ] Tests sur device physique (iPhone + Android) en mode release (pas debug)
- [ ] Vérifier deep links (`https://kilimandjaro.app/duel/...`) fonctionnent
- [ ] Vérifier paiements IAP en sandbox (App Store Sandbox + Google Play test)
- [ ] App Tracking Transparency dialog s'affiche (iOS 14.5+)
- [ ] Vérifier Firebase Crashlytics reçoit les events (force un crash dans
      `_BootGate`)
- [ ] Sur prod : vérifier que les anciens utilisateurs (avant Phase 4) voient
      bien leur wallet `cauris` + `ownedPacks` préservé (bootstrap silencieux
      au prochain MyPacks)

### 7.5 Phasage release

**Recommandé** :
1. Internal Testing (jour J) : équipe + 5-10 beta testers
2. Closed Testing (J+3) : 50-100 utilisateurs
3. Open Testing (J+7) : public si stable
4. Production (J+10) : rollout 5% → 25% → 50% → 100% sur 1 semaine

---

## 8. Rollback procedures

### 8.1 Rollback Firestore rules

Firebase Console → Firestore → Rules → "Edit history" → sélectionner version
précédente → "Restore". Effet immédiat (~30 sec propagation).

### 8.2 Rollback Cloud Functions

```bash
# Lister les revisions Cloud Run de la function
gcloud run revisions list --service=publishpack --region=europe-west1 \
  --project=kilimandjaro-prod

# Rollback vers une revision précédente
gcloud run services update-traffic publishpack \
  --to-revisions=publishpack-00001-abc=100 \
  --region=europe-west1 \
  --project=kilimandjaro-prod
```

### 8.3 Rollback catalog/index

Si un `publishPack` casse le catalog (ex: pack indisponible), utiliser la CF
`rollbackPack` :

```javascript
// firebase functions:shell --project kilimandjaro-prod
> rollbackPack({packId: 'culture_ci', toVersion: 1})
// → bascule content_packs/culture_ci sur v1, le bundle reste fallback
```

### 8.4 Rollback app release

App Store Connect / Play Console → "Halt rollout" puis "Resume rollout" sur la
version précédente. App stores ne permettent pas de "downgrade" — il faut
publier une nouvelle release (bump version + revert code).

---

## 9. Monitoring & alertes

### 9.1 Cloud Functions

Firebase Console → Functions → onglet "Logs" pour chaque CF :
- Erreurs `permission-denied` → claim manquant côté users
- Erreurs `failed-precondition` (validation/wallet) → normal si user UX
- Erreurs `internal` → bug → investiguer immédiatement
- Erreurs `unauthenticated` → user pas loggé (normal pour les CFs auth-required)

### 9.2 Alertes recommandées

Cloud Monitoring → Alerting :

1. **CF error rate > 5%** sur n'importe quelle wallet/admin CF en 5 min →
   notification Slack/email
2. **CF latency p95 > 3s** → idem (transactions Firestore lentes peuvent
   indiquer une saturation index)
3. **Firestore writes > 10k/hour** sur `users/{uid}/inventory_audit/` →
   possible attaque DDoS / boucle infinie côté client
4. **Storage egress > 10 GB/jour** sur `packs/v2/**` → vérifier que les
   clients utilisent bien le cache local et ne refetch pas en boucle

### 9.3 Dashboards

- **Firebase Analytics** : MAU, sessions, screen views (incluant `shop_view`,
  `my_packs_view`, `unlock_pack_dialog`)
- **Firebase Crashlytics** : erreurs crash rate, comparer avant/après release
- **GCP Cloud Console** : Cloud Functions latency, error rate, invocations

---

## 10. Migration utilisateurs existants (pré-Phase 4)

Les utilisateurs qui avaient déjà l'app installée avant Phase 4 ont leur
wallet en SharedPreferences uniquement. Pour les migrer :

### 10.1 Bootstrap silencieux au prochain boot

Le client appelle `bootstrapWallet` automatiquement au premier
`unlockPack` ou `creditCauris` qui rencontre `wallet non initialisé`.

**À implémenter** (hors scope Phase 4 immédiate) : un bootstrap proactif au
boot post-deploy pour synchroniser tout de suite. Mais cf OTA v0.2 — pas de
charge réseau au boot recommandé.

**Solution actuelle** : le bootstrap se fait paresseusement :
- À la première tentative d'unlock → bootstrap puis retry (transparent)
- Le cauris local est cap à `CAURIS_BOOTSTRAP_CAP=2000` pour anti-cheat. Les
  users qui ont accumulé plus (légitimement via IAP + grind) auront leur
  solde tronqué au bootstrap.

### 10.2 Mitigation : grace period

Pour les premiers users post-Phase 4, considérer bumper `CAURIS_BOOTSTRAP_CAP`
temporairement à 10_000 (via Remote Config si on l'ajoute, ou un override dans
le code de la CF avec date butoir). Décision produit.

---

## 11. Sécurité — checklist finale avant ouverture publique

- [ ] Firestore rules : aucune ouverture `allow read, write: if true;` sur
      autre chose que `catalog/*`, `content_packs/*`, `content_index/*`
- [ ] Storage rules : `packs/v2/**` lecture publique, autres chemins
      authentification requise
- [ ] App Check enabled sur les CFs sensibles (TODO Phase 4.8 — pour l'instant
      `enforceAppCheck: false` partout)
- [ ] Receipts IAP : validation crypto Apple/Google **À FAIRE** Phase 4.1
      (actuellement `verified: false` dans `iap_receipts/`)
- [ ] Audit logs : `users/{uid}/inventory_audit` activé + retention >= 90j
      (GDPR friendly)
- [ ] Service accounts : jamais commit dans le repo (`.gitignore` à vérifier)
- [ ] API keys Firebase Web : protégées par App Check + Firestore rules + Auth
      domain whitelist (les apiKey JS sont semi-publiques par design Firebase)
- [ ] Cloud Functions secrets (futures clés Apple `.p8` / Google service
      account JSON) : Firebase Secret Manager, jamais en clair dans le code

---

## 12. Annexe — commandes utiles

### Vérifier l'état d'un déploiement

```bash
# Quelles CFs sont déployées sur prod ?
firebase functions:list --project kilimandjaro-prod

# Quelle version de rules est active ?
firebase firestore:rules:get --project kilimandjaro-prod

# Quels packs sont dans Firestore ?
gcloud firestore export gs://kilimandjaro-prod-backups/dump_$(date +%Y%m%d) \
  --collection-ids=catalog,packs,content_packs,content_index \
  --project=kilimandjaro-prod
```

### Backup manuel avant deploy critique

```bash
gcloud firestore export gs://kilimandjaro-prod-backups/pre_phase4_$(date +%Y%m%d_%H%M%S) \
  --project=kilimandjaro-prod
```

Restauration : `gcloud firestore import gs://...` (lent sur gros volumes).

### Test charge légère

```bash
# 100 appels concurrents syncWallet (need user token)
for i in {1..100}; do
  curl -X POST "https://europe-west1-kilimandjaro-prod.cloudfunctions.net/syncWallet" \
    -H "Authorization: Bearer <user_id_token>" \
    -H "Content-Type: application/json" \
    -d '{"data":{}}' &
done
wait
# Surveiller dashboard Functions → invocations + erreurs
```

---

**Auteur** : Claude + Arnaud, juin 2026
**Mis à jour** : à chaque modification du flow deploy (Phase 5 polish, etc.)

**Précédents docs liés** :
- [`backoffice_schema.md`](backoffice_schema.md) — Phase 1-2
- [`wallet_server_schema.md`](wallet_server_schema.md) — Phase 4
- [`ota_v2_design.md`](ota_v2_design.md) — Contraintes OTA jetsam iOS 26
- [`memory/phase4_manual_setup.md`](memory/phase4_manual_setup.md) — actions manuelles RC/AdMob/stores
- [`memory/remote_config_keys.md`](memory/remote_config_keys.md) — détail 12 clés
