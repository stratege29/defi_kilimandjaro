# Images IA (OpenAI) — secret Firebase + dashboard

Génération d'images de marque dans un **style signature cohérent** (illustration éditoriale,
grain risographie, golden hour, palette vert nuit + or + terracotta + crème), **côté serveur**.
La clé OpenAI vit en **secret Firebase** — tu ne la manipules jamais en local ni dans le chat.

- **Fonction** : `igGenerateImages` (callable, propriétaire) — génère via OpenAI, stocke sur Storage, écrit la galerie dans Firestore `ai_images`.
- **UI** : onglet **Images IA** du backoffice (`tools/admin_console_web`) — générer / prévisualiser / ajouter à la file en un clic.
- **Style** : défini dans `functions/src/social/genImages.ts` (constante `STYLE`), modifiable.

## 1. Enregistrer la clé OpenAI (tu la saisis, pas dans le chat)
```bash
cd /Users/arnaudkossea/development/defi_kilimandjaro
firebase functions:secrets:set OPENAI_API_KEY
# colle ta clé sk-... quand c'est demandé, puis Entrée
```

## 2. Déployer (fonction + règles + dashboard)
```bash
cd tools/admin_console_web && npm run build && cd ../..
firebase deploy --only "functions:igGenerateImages,firestore:rules,hosting"
```

## 3. Utiliser (sans Terminal ensuite)
Ouvre la console admin → onglet **Instagram → 🎨 Images IA** :
1. clique **Générer** sur un sujet (Abidjan, baobab, attiéké, joueur…) → l'image apparaît,
2. **Ajouter** → ouvre le formulaire pré-rempli (URL + légende) → tu écris la légende, choisis la date, Enregistrer.
L'image part dans la même file que l'autopilote.

## Sujets disponibles
Villes (Abidjan, Dakar, Lagos, Marrakech, Yamoussoukro), nature/sommets (Kilimandjaro,
baobab), culture (masque, balafon), food (attiéké, alloco), visages (joueur, amis), duel.
Ajoute/édite dans `SPECS` (genImages.ts).

## Coût & qualité
`gpt-image-1` : ~**0,16 $/image** en « high », ~0,06 $ en « medium ». 14 sujets ≈ 1-2 $.
Pour réduire : passe `quality: "medium"` dans l'appel (ou je le change).

## Notes
- Le **style illustré assumé** rend l'IA acceptable même pour la food et les visages (ça se lit comme de l'art, pas comme une fausse photo).
- Le texte/branding n'est PAS incrusté : ces images se postent en illustration + légende. Si tu veux le voile+texte par-dessus, dis-le moi (je l'applique via `photo_card.py`).
- Variante 100% local (sans Firebase) : `functions/scripts/gen_images_openai.py` (clé en variable d'env).
