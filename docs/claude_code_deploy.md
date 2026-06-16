# Brief à coller dans Claude Code

> Copie tout le bloc ci-dessous dans Claude Code (lancé dans le dossier du projet).
> Remplace `sk-OPENAI...` par ta vraie clé au moment voulu (ne la mets pas dans un fichier versionné).

---

Tu travailles dans le repo `/Users/arnaudkossea/development/defi_kilimandjaro` (Flutter + Firebase).
Projet Firebase : **kilimandjaro-dev**, région **europe-west1**, site hosting **kilimandjaro-admin-dev**.
Une page Instagram **@defi_kilimandjaro** est automatisée : Cloud Functions + file Firestore **`instagram_queue`** (1 post/jour, publié par `publishScheduledInstagramPost`).

**CONTRAINTE ABSOLUE :** ne JAMAIS modifier, re-dater, re-uploader ni re-publier un document de `instagram_queue` dont `posted == true`. Les scripts fournis respectent déjà ça (append-only ou refresh des non-publiés uniquement). N'utilise PAS `apply_master_plan.js --commit` (il réinitialise tout) — sauf demande explicite.

Pré-requis (refais-les seulement si une commande échoue pour cause d'auth) :
- `firebase login`
- `gcloud auth application-default login`
- Le secret `INSTAGRAM_SOCIAL_TOKEN` existe déjà.

Fais ces tâches dans l'ordre, et **après chaque dry-run, vérifie qu'aucun post `posted==true` n'apparaît avant de lancer `--commit`** :

### 1. Déployer le dashboard + nouvelles fonctions + règles
```bash
cd tools/admin_console_web && npm install && npm run build && cd ../..
firebase deploy --only "functions:igInsights,functions:igPublishPost,functions:igGenerateImages,firestore:rules,hosting"
```

### 2. Secret OpenAI (pour la génération d'images serveur via le dashboard)
```bash
firebase functions:secrets:set OPENAI_API_KEY      # colle ta clé sk-...
firebase deploy --only functions:igGenerateImages  # pour lier le secret
```

### 3. Générer les images IA restantes (3 déjà faites : abidjan, baobab, attieke)
```bash
python3 -m venv /tmp/igvenv && /tmp/igvenv/bin/pip install openai pillow numpy
env OPENAI_API_KEY=sk-OPENAI... /tmp/igvenv/bin/python functions/scripts/gen_images_openai.py \
  dakar lagos marrakech yamoussoukro kilimandjaro balafon masque alloco player friends duel
# images brutes -> docs/instagram_assets/ai/
```

### 3b. Appliquer le voile + texte de marque (habillage)
```bash
/tmp/igvenv/bin/python functions/scripts/apply_ai_overlay.py
# cartes habillées -> docs/instagram_assets/ai/cards/  (polices embarquées dans functions/scripts/fonts/)
```

### 4. Rafraîchir les visuels des posts NON publiés (patterns / thèmes crème-vert / accents)
```bash
node functions/scripts/refresh_unposted_media.js            # DRY-RUN : vérifie "publié, intact" sur les posts déjà sortis
node functions/scripts/refresh_unposted_media.js --commit
```

### 5. Ajouter les posts images IA (cartes habillées voile+texte), datés APRÈS le dernier post
```bash
node functions/scripts/add_ai_posts.js            # DRY-RUN
node functions/scripts/add_ai_posts.js --commit
```
(le script lit `docs/instagram_assets/ai/cards/CARD_*.png` produites à l'étape 3b)

### Vérification finale
Ouvre **https://kilimandjaro-admin-dev.web.app** → onglet **Instagram → Calendrier** : confirme que les posts publiés sont intacts et que les nouveaux posts IA sont bien ajoutés à la suite. Tu peux aussi générer des images depuis l'onglet **🎨 Images IA**.

---

## Notes (pour toi, Koss — pas à coller)
- Les images IA sont habillées avec le **voile + texte de marque** (comme la démo Abidjan/baobab/attiéké), via `apply_ai_overlay.py`. Les **polices sont embarquées** dans `functions/scripts/fonts/` → l'habillage tourne en autonomie dans Claude Code (aucune install de police).
- Le texte/accent de chaque carte est défini dans `apply_ai_overlay.py` (dict `CARDS`) — éditable.
- `refresh_unposted_media.js` pousse les visuels à patterns/thèmes **sans** toucher aux posts déjà sortis.
- Pour committer ces nouveaux fichiers : `functions/scripts/fonts/` + `logo.png` + `generate.py/patterns.py/photo_card.py/apply_ai_overlay.py` sont nécessaires à l'habillage. Tu peux les versionner ou les gitignorer selon ta préférence (s'ils sont gitignorés, garde-les en local).
