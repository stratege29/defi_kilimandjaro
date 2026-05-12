# Déploiement — Kilimandjaro

Ce guide couvre les **5 étapes** mises en place dans cette PR :

1. [Curator agent LLM (Cloud Function)](#1-curator-agent-llm)
2. [Console de modération (admin_console Flutter web)](#2-console-de-modération)
3. [Upload des seed packs vers Firebase](#3-upload-des-seed-packs)
4. [Native setup App Check](#4-native-setup-app-check)
5. [Déploiement Cloud Functions](#5-déploiement-cloud-functions)

---

## Pré-requis (une fois par machine)

```bash
# Firebase CLI + auth
npm i -g firebase-tools
firebase login

# Application Default Credentials (utilisées par les scripts Node)
gcloud auth application-default login
gcloud config set project kilimandjaro-prod   # ou kilimandjaro-dev
```

Cible Node 20 (cf. `functions/package.json`).

---

## 1. Curator agent LLM

Implémenté dans `functions/src/curation/`. Trois providers :

| Provider     | Modèle défaut       | Variable d'env / secret                   |
|--------------|---------------------|-------------------------------------------|
| `vertex` ⭐  | `gemini-2.0-flash`  | ADC + IAM `roles/aiplatform.user`         |
| `anthropic`  | `claude-opus-4-7`   | env / secret `ANTHROPIC_API_KEY`          |
| `heuristic`  | déterministe        | (aucune — failsafe local/CI)              |

### Activer Vertex (provider par défaut)

```bash
gcloud auth login
gcloud config set project $PROJECT          # kilimandjaro-dev ou -prod
gcloud services enable aiplatform.googleapis.com
gcloud projects add-iam-policy-binding $PROJECT \
  --member="serviceAccount:$PROJECT@appspot.gserviceaccount.com" \
  --role="roles/aiplatform.user"
```

Aucun secret à gérer : Cloud Functions s'authentifie auprès de Vertex via
ADC, avec le service account `$PROJECT@appspot.gserviceaccount.com`.

### Bascule vers Anthropic (optionnel)

```bash
firebase functions:secrets:set ANTHROPIC_API_KEY
# Puis dans functions/src/curation/curateSubmission.ts :
#   - ajouter `secrets: [anthropicApiKey]` au trigger
#   - exporter CURATOR_PROVIDER=anthropic via firebase functions:config
```

### Tester en local

```bash
cd functions
npm install
npm test                              # unit (heuristic)
firebase emulators:start --only functions,firestore
# Dans un autre shell :
firebase emulators:exec --only firestore \
  "node -e 'require(\"firebase-admin\").initializeApp().firestore().collection(\"submissions\").add({authorUid:\"u1\",question:\"…\",answer:\"BAOBAB\",country:\"CI\",tags:[\"arbre\"],difficulty:2,locale:\"fr-CI\",status:\"pending\",createdAt:new Date().toISOString()})'"
```

---

## 2. Console de modération

`tools/admin_console/` — Flutter web indépendant.

### Bootstrap initial

```bash
cd tools/admin_console
flutter create . --platforms=web --org com.ultimesgriots --project-name kilimandjaro_admin
flutter pub get
flutterfire configure --project=kilimandjaro-prod \
  --platforms=web --out=lib/firebase_options.dart
flutter run -d chrome --web-port=5050
```

### Donner le rôle `moderator` à un user

```bash
# Une fois, depuis un script Node admin :
node -e '
const a=require("firebase-admin");
a.initializeApp();
a.auth().setCustomUserClaims("UID_DU_MODERATEUR",{role:"moderator"})
  .then(()=>console.log("ok"));
'
```

### Build + hosting (optionnel)

```bash
flutter build web --release --web-renderer canvaskit
# Hosting cible séparée si besoin (admin.kilimandjaro.app)
firebase target:apply hosting admin tools-admin-kilimandjaro
firebase deploy --only hosting:admin
```

---

## 3. Upload des seed packs

Les packs `*.json.gz` sont produits dans `build/seed_packs/` (par un build
side, non couvert ici). Le manifeste `manifests.json` y est aussi écrit.

### Upload + seed Firestore

```bash
# Sécheresse — vérifier ce qui sera fait :
tools/upload_seeds.sh kilimandjaro-prod.appspot.com --dry-run

# Pour de vrai :
tools/upload_seeds.sh kilimandjaro-prod.appspot.com
```

Effets :

1. `gsutil -m cp -r build/seed_packs/**/*.gz gs://<bucket>/packs/v2/`
2. Upsert dans Firestore collection `packs/{packId}`, avec champ `url`
   réécrit vers `https://firebasestorage.googleapis.com/v0/b/<bucket>/o/...`.

### Format manifest attendu

```jsonc
{
  "packs": [
    {
      "id": "village_des_or",
      "version": 2,
      "locale": "fr-CI",
      "title": "Village des Or",
      "objectPath": "village_des_or.json.gz",
      "size": 12345,
      "sha256": "abc...",
      "tags": ["cuisine", "masque"]
    }
  ]
}
```

---

## 4. Native setup App Check

Code Flutter activé dans `lib/main.dart` (after `Firebase.initializeApp`).
Provider :

- **Android release** → Play Integrity
- **iOS release**     → DeviceCheck (App Attest auto)
- **Debug**           → Debug provider (token à allow-lister)

### Console Firebase — Android

1. **Build → App Check → Apps → Android** : enregistrer le bundle
   `com.ultimesgriots.kilimandjaro` avec **Play Integrity**.
2. Console Google Play → API Play Integrity → activer pour le projet.
3. Lancer un build debug : copier le token affiché dans `logcat | grep
   DebugAppCheckProvider` puis **App Check → Apps → Android → ⋮ → Manage
   debug tokens** → coller.

### Console Firebase — iOS

1. **Apple Developer Portal** → Identifiers → App ID
   `com.ultimesgriots.kilimandjaro` → activer **App Attest**.
2. **Build → App Check → Apps → iOS** : enregistrer Team ID + Bundle ID
   avec provider **App Attest** (DeviceCheck en fallback iOS < 14).
3. Build Xcode debug → console : `filter FIRDebugAppCheckProvider` →
   copier le token → **App Check → Apps → iOS → ⋮ → Manage debug
   tokens** → coller.

### Enforcement

Une fois les debug tokens allow-listés et un build release validé,
passer en **Enforce** sur :

- Realtime Database (duels)
- Firestore (profils, submissions, packs)
- Cloud Functions (`curateSubmission`, `requestMatch`, `validateWord`)

---

## 5. Déploiement Cloud Functions

```bash
cd functions
npm install
npm run build
npm run lint
npm test

# Première fois (déclare les secrets) :
firebase functions:secrets:set ANTHROPIC_API_KEY

# Déployer :
firebase deploy --only functions

# Ou cibler une fonction précise :
firebase deploy --only functions:curateSubmission
```

### Vérifier que ça tourne

```bash
firebase functions:log --only curateSubmission
```

Puis créer une soumission test depuis l'admin console (ou directement
via `firebase firestore:write submissions/{auto} '{...}'`).

---

## Ordre de bootstrap recommandé

1. Cloud Functions deploy (étape 5) — le trigger est passif tant qu'il n'y
   a pas de soumission.
2. App Check setup (étape 4) — sinon les écritures depuis l'app seront
   rejetées en mode Enforce.
3. Upload seeds (étape 3) — populate `packs/` avant le premier launch.
4. Admin console (étape 2) — déployer une fois qu'il y a des soumissions
   à modérer.
5. Curator (étape 1) — déjà déployé en 5, simplement vérifier la file.
