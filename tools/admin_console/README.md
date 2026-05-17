# Kilimandjaro Admin Console

Backoffice **Flutter web** pour Kilimandjaro :

- **Gestion CRUD des packs de contenu** (collection `content_packs`)
- **Gestion CRUD des questions** par pack (sous-collection `questions`)
- **Bouton "Publier le pack"** → déclenche la Cloud Function `publishPack`
  qui rebuild le gz, hash, upload Storage et met à jour le manifest
  Firestore. Les apps captent la nouvelle version au prochain démarrage
  via `ManifestSyncService` (zéro changement côté app).
- **File de modération UGC** (existante) accessible sous `/moderation`.

> Décision d'architecture : Option B (hybride). Le backoffice écrit
> directement dans Firestore ; seul le bouton "Publier" touche le pipeline
> OTA via Cloud Function. Voir `functions/src/curation/publishPack.ts`.

---

## Stack

- Flutter web 3.27+
- Riverpod 2.6 (state management)
- go_router 14 (routing imbriqué : `/packs/:packId/questions/:questionId`)
- firebase_auth + cloud_firestore + cloud_functions

---

## Architecture

```
lib/
  main.dart                          # bootstrap Firebase + ProviderScope
  src/
    router.dart                      # go_router avec ShellRoute + AuthGate
    app_shell.dart                   # NavigationRail + AppBar
    auth/
      auth_providers.dart            # authStateProvider, adminClaimsProvider
      auth_gate.dart                 # contrôle role: admin | moderator
    moderation/                      # file UGC existante (inchangée)
    packs/
      domain/
        pack.dart                    # modèle Pack + (un)serialization
        question.dart                # modèle Question (format v3)
        question_validators.dart     # validators purs (testés)
      data/
        packs_repository.dart        # Firestore + Cloud Functions
      presentation/
        packs_list_view.dart         # liste + bouton "Nouveau pack"
        pack_edit_view.dart          # édition métadonnées + "Publier"
        questions_list_view.dart     # liste paginée + filtres
        question_edit_view.dart      # formulaire avec preview live
```

Le routing applique l'`AuthGate(requireAdmin: true)` au niveau ShellRoute :
sans claim `role: admin`, l'utilisateur voit "Accès refusé".

---

## Setup initial

```bash
cd tools/admin_console
flutter pub get
flutterfire configure --project=kilimandjaro-dev \
  --platforms=web --out=lib/firebase_options.dart
```

> `lib/firebase_options.dart` est gitignored. Pour un déploiement multi-env
> (dev/prod), utiliser `flutter run --dart-define=FIREBASE_PROJECT=…` et
> deux fichiers `firebase_options.<env>.dart`.

---

## Lancer en dev

```bash
flutter run -d chrome --web-port=5050
```

Connexion Google. **Sans le custom claim `role: admin`, accès refusé.**

---

## Provisionner le claim `admin`

Le claim est attribué out-of-band avec firebase-admin SDK :

```bash
# 1. récupérer l'uid (visible en bas de l'écran "Accès refusé" après login)
# 2. depuis n'importe quel script Node avec ADC :
node -e "
  const admin = require('firebase-admin');
  admin.initializeApp({ projectId: 'kilimandjaro-dev' });
  admin.auth()
    .setCustomUserClaims('VOTRE_UID', { role: 'admin' })
    .then(() => console.log('OK — relogger l\\'utilisateur'));
"
```

Le claim n'est pris en compte qu'au prochain refresh du token ID — l'app
appelle `getIdTokenResult(true)` au boot pour le forcer.

---

## Workflow d'ajout de contenu (recommandé)

1. **Créer un pack** : `/packs` → bouton `+ Nouveau pack` → entrer
   `pack_id` (validé regex `^[a-z][a-z0-9_]{1,40}$`).
2. **Éditer métadonnées** : nom, description, prix, `enabled`. **Sauvegarder.**
3. **Ajouter des questions** : `/packs/{packId}/questions` →
   `+ Nouvelle question`. Le formulaire valide en live :
   - `answer` : 4 à 8 lettres, accents auto-strippés
   - `letters_pool` : auto-calculé (multiset strict des lettres de `answer`)
   - `answer_normalized` : auto-calculé (lowercase ASCII)
   - `estimated_time_s` : déterminé par la difficulté (20/25/30/35/40)
4. **Publier** : retour sur `/packs/{packId}` → bouton `Publier le pack`.
   - Confirmation requise.
   - Bump `current_version` systématique.
   - Cloud Storage : `packs/v2/{packId}/{packId}-v{N}.json.gz`.
   - Firestore `content_packs/{packId}` mis à jour atomiquement.
   - `content_index/global.packs` enrichi.
5. **Distribution** : les apps détectent la nouvelle version au prochain
   démarrage et téléchargent le gz (offline-first, hash vérifié).

---

## Migration des packs existants (one-shot)

Une fois en setup, lancer **une fois** :

```bash
# Pré-requis : gcloud auth application-default login
cd tools/scripts
npm install
node migrate_existing_to_firestore.mjs --project kilimandjaro-dev
# --dry-run pour simuler sans écrire
```

→ Seed `content_packs/{culture_ci, crack_nouchi}` (métadonnées tirées
de `_index.json`) et toutes leurs questions (starter + ota merged).
Le `enabled` reste à `false` jusqu'à validation manuelle dans le
backoffice. La 1re publication via le bouton crée le manifest et le gz.

---

## Déploiement

```bash
# Cloud Function + rules + storage rules
firebase deploy --only functions:publishPack,firestore:rules

# Build web + hosting admin
flutter build web --release
firebase deploy --only hosting:admin
```

---

## Sécurité

- `firestore.rules` :
  - `content_packs/{packId}` : `allow write: if isAdmin()` (claim `role: admin`)
  - `content_packs/{packId}/questions/{questionId}` : idem
- Cloud Function `publishPack` : check `auth.token.role == 'admin'` server-side
- Storage `packs/` : lecture publique, écriture serveur uniquement
- L'app web est servie sur un domaine séparé (`admin.kilimandjaro.app`)
  pour isoler les cookies du jeu

---

## Tests

```bash
cd tools/admin_console
flutter test
```

- `test/question_validators_test.dart` : 14 tests purs (normalisation,
  validation, letters_pool multiset)

```bash
cd functions
npm test
```

- `test/publishPack.test.ts` : tests du payload builder (déterminisme,
  détection langues)

> Pour tester la Cloud Function end-to-end, lancer les emulators :
> `firebase emulators:exec --only firestore,functions,storage "npm test"`.

---

## Limitations connues (v1)

- Pas d'upload d'images depuis le backoffice (Phase 4)
- Pas de drafts : toute édition est live dans Firestore (mais invisible des
  users tant que `publishPack` n'est pas appelé)
- Pas de stats/analytics par pack
- Pas de A/B testing par question
- Pagination des questions = côté client (limit Firestore 500 par défaut) —
  passer à `startAfterDocument` pour scaler à > 5000 questions par pack
- Pas de versioning des éditions (audit log) — capter via Firestore Audit
  Logs côté GCP si besoin
