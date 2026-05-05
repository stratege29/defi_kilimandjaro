# Firebase setup — kilimandjaro-dev

À faire **une seule fois** dans la console Firebase ([console.firebase.google.com](https://console.firebase.google.com/project/kilimandjaro-dev)) avant le premier test du défi 1v1.

## 1. Authentication

`Build → Authentication → Sign-in method` :
- ✅ Activer **Anonymous**

(Google et Apple Sign-In viennent en Phase 6.1+ pour le matchmaking ELO et la persistance cross-device.)

## 2. Realtime Database

`Build → Realtime Database → Create Database` :
- Région : **United States (us-central1)** par défaut. Si tu choisis une autre région (ex. europe-west1), mets à jour `databaseURL` dans `lib/firebase_options.dart` avec le format approprié :
  ```
  https://kilimandjaro-dev-default-rtdb.europe-west1.firebasedatabase.app
  ```
- Mode : **Locked mode** (les règles strictes seront déployées juste après)

## 3. Déployer les règles de sécurité

Depuis la racine du repo, une fois `firebase login` à jour :

```bash
firebase use kilimandjaro-dev
firebase deploy --only database
```

Les règles dans `database.rules.json` autorisent :
- Lecture/écriture d'un match seulement aux joueurs participants ou au créateur.
- Le `secret` n'est lisible que par le créateur.
- L'`answer` n'est lisible que par les participants.
- Chaque joueur ne peut écrire que dans son propre sous-noeud `players/{uid}`.

## 4. Vérification

Après l'app installée :
- Au lancement, regarder les logs : `Firebase initialized` + un UID anonyme dans Auth Console (`Authentication → Users`).
- Créer un duel depuis le device A → vérifier `/matches/{matchId}` apparaît dans la console RTDB.
- Scanner depuis le device B → vérifier que `players/{uid}` du B s'ajoute et `phase` passe à `active`.

## 5. (Optionnel) Cloud Functions pour matchmaking ELO — Phase 6.1+

Pas requis pour le défi local QR. Activé en Phase 6.1 pour la queue ELO et l'anti-cheat serveur des matchs random.
