# Kilimandjaro Admin Console

Console de modération humaine — Flutter web séparé du jeu mobile.

Cible la même base Firestore (`submissions/{id}`) que la Cloud Function `curateSubmission`. Affiche les soumissions avec `status == 'review'` triées par score décroissant ; permet d'approuver/rejeter en un clic.

## Bootstrap

```bash
cd tools/admin_console
flutter create . --platforms=web --org com.ultimesgriots --project-name kilimandjaro_admin
flutter pub get
flutterfire configure --project=kilimandjaro-prod \
  --platforms=web --out=lib/firebase_options.dart
```

> Le scaffold initial se base sur le `lib/firebase_options.dart` stub fourni.
> Ne committe **pas** la version générée si elle contient des clés sensibles —
> ajoute-la à `.gitignore` ou utilise un projet Firebase dédié à la console.

## Lancer

```bash
flutter run -d chrome --web-port=5050
```

Connexion Google requise. **Le rôle `moderator`** doit être positionné comme custom claim sur le compte Firebase Auth (out-of-band, via Firebase Admin SDK) — sans cela, les règles Firestore refuseront les écritures de modération.

## Sécurité

- Les règles Firestore (à compléter dans `firestore.rules`) doivent vérifier
  `request.auth.token.role == 'moderator'` pour toute écriture sur
  `submissions/{id}` après curation.
- L'app est servie sur un domaine séparé (`admin.kilimandjaro.app`) pour
  isoler les cookies du jeu.

## Build

```bash
flutter build web --release --web-renderer canvaskit
firebase deploy --only hosting:admin
```
