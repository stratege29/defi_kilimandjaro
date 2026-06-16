# Autopilote Instagram — Cloud Function (déploiement)

> La publication automatique tourne **côté serveur** dans tes Cloud Functions Firebase
> (l'environnement Cowork est cloisonné et ne peut pas joindre l'API Instagram).
>
> Fonctions ajoutées (`functions/src/social/`) :
> - **`publishScheduledInstagramPost`** — planifiée chaque jour à 19h30 (Europe/Paris), publie le post dû.
> - **`igPublishDueNow`** — déclenchement manuel (admin) pour tester sans attendre.
>
> Source des posts : collection Firestore **`instagram_queue`**. Médias : **Firebase Storage** (lecture publique).

---

## 1. Enregistrer le token comme secret (une fois)

```bash
firebase functions:secrets:set INSTAGRAM_SOCIAL_TOKEN
# colle ton token longue durée quand c'est demandé, puis Entrée
```
(Nom du secret utilisé par le code : **`INSTAGRAM_SOCIAL_TOKEN`**.)

Le token n'est **jamais** en clair dans le code : il est injecté dans la fonction au déploiement.
Pour le renouveler (~tous les 50 jours), relance la même commande avec un token frais.

> L'`IG_USER_ID` (`17841423397309250`) est déjà la valeur par défaut dans le code.
> Pour le changer sans redéployer le code : `firebase functions:config` ou un paramètre `IG_USER_ID`.

## 2. Rendre les visuels lisibles publiquement (Storage)

L'API Instagram télécharge chaque média depuis une **URL publique**. Le script de seed
(étape 3) téléverse les PNG et les rend publics automatiquement. Si tu uploades à la main,
assure-toi que les fichiers sont en **lecture publique**.

## 3. Téléverser les visuels + remplir la file (une commande)

```bash
cd functions
# Connexion Firebase si besoin : firebase login
node scripts/seed_instagram_queue.js          # dry-run : montre ce qui serait fait
node scripts/seed_instagram_queue.js --commit  # téléverse + crée les docs instagram_queue
```

Le script lit `scripts/instagram_seed_data.json` (les 14 jours + légendes), téléverse les
images depuis `docs/instagram_assets/` vers Storage (dossier `social/ig/`), récupère les URLs
publiques et crée un document par post dans **`instagram_queue`** (avec `posted: false`).

> Les **Reels** (J2, J6, J9) ont besoin d'une **vidéo** hébergée — tant que le montage n'est
> pas fait, ces entrées restent en `posted: true` (ignorées). On les activera après le montage.

## 4. Déployer

```bash
cd functions
npm run build
firebase deploy --only functions:publishScheduledInstagramPost,functions:igPublishDueNow
```

## 5. Tester tout de suite (sans attendre 19h30)

Option A — depuis le shell Firebase :
```bash
cd functions
npm run shell
> igPublishDueNow({})
```

Option B — appeler `igPublishDueNow` depuis ta console admin (utilisateur avec le rôle admin).

La fonction publie le **post dû le plus ancien** et le marque `posted: true`. Relance pour le suivant.

---

## Régler l'heure / le rythme
- Heure : change `schedule: "30 19 * * *"` dans `publishInstagram.ts` (cron, Europe/Paris).
- 1 post/jour par défaut. Pour plusieurs créneaux, on dupliquera la planification (12h30, 19h30).

## Comment ça marche (résumé)
1. `instagram_queue` contient les posts datés (`posted: false`).
2. Chaque jour, la fonction prend le 1ᵉʳ post dont `date <= aujourd'hui` et `posted == false`.
3. Elle publie via l'API (image / carrousel / reel) et marque `posted: true` + `postedAt` + `mediaId`.

## Dépannage
- **« Rôle de développeur insuffisant »** au runtime : le token n'est plus valide → refais l'étape 1.
- **Média qui n'apparaît pas** : vérifie que l'URL Storage est bien publique (ouvre-la dans un navigateur).
- **Reel en erreur** : la vidéo doit être 9:16, hébergée publiquement, format MP4.
- Logs : `firebase functions:log --only publishScheduledInstagramPost`.
