# Onglet « Instagram » du backoffice

Intégré **dans la console admin existante** (`tools/admin_console_web`, React/Vite) comme
nouvel onglet du rail de navigation — pas de site séparé. Accès réservé au compte admin
habituel (connexion Google).

- **Composant** : `tools/admin_console_web/src/Instagram.jsx` (branché dans `App.jsx`).
- **Backend** : Cloud Functions `igInsights` (stats Instagram) et `igPublishPost` (publier un post précis).
- **Sécurité** : règles Firestore — `instagram_queue` accessible au propriétaire (`arnaudkossea@gmail.com`) / admin.

## Trois sous-onglets
- **📈 Stats** — abonnés, nb de publications, engagement moyen, et les publications récentes en live (likes/commentaires, lien vers le post). Bouton « Rafraîchir » → `igInsights`.
- **🗓️ Calendrier** — tous les posts de `instagram_queue` (date, format, statut), **éditer / ajouter / supprimer**, et **« Publier »** un post immédiatement (`igPublishPost`).
- **🚀 Playbook** — les recommandations de l'audit (ratio Reels, 100 premiers abonnés, hooks, hashtags, collabs).

## Déploiement

```bash
cd /Users/arnaudkossea/development/defi_kilimandjaro/tools/admin_console_web
npm install          # seulement la première fois
npm run build
cd ../..
firebase deploy --only "functions:igInsights,functions:igPublishPost,firestore:rules,hosting"
```

Puis ouvre ta console admin (**https://kilimandjaro-admin-dev.web.app**) → onglet **Instagram**.

## Notes
- Le composant écrit dans la **même file** que l'autopilote : tout ajout/édition est pris en compte par la publication quotidienne automatique (19h30 Paris).
- Stats : `followers_count` et `media_count` arrivent vite ; le détail par post s'enrichit avec le temps.
- Le fichier autonome `tools/ig_dashboard/index.html` (première version séparée) est **superseded** par cet onglet — tu peux l'ignorer.
