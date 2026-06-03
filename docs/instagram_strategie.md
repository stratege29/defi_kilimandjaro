# Instagram @kilimandjaro — Faisabilité & plan d'autopilote

> Compte Instagram du jeu **Kilimandjaro — Sagesse Ivoirienne** (Ultimes Griots), géré en autopilote par Claude. Mode choisi : **auto total via API Meta**.

---

## 1. Faisabilité — verdict

| Volet | Faisable 100 % par Claude ? | Détail |
|---|---|---|
| Ligne éditoriale, calendrier, idées | ✅ Oui | Stratégie + planning complets |
| Légendes, hashtags, réponses-types | ✅ Oui | Génération par lots |
| Visuels (images, carrousels) | ✅ Oui | Générés à partir du thème ivoirien du jeu |
| Reels / vidéos | ⚠️ Partiel | Scripts + storyboards oui ; montage vidéo = outil externe |
| Publication automatique | ✅ Oui *(via API Meta)* | Après config initiale faite **une fois ensemble** |
| Création du compte Meta + tokens | ❌ Non | Demande tes identifiants et des clics côté Meta |
| DM automatisés | ❌ Non autorisé | Interdit par les règles Instagram |

**Conclusion** : « 100 % géré par Claude » est réaliste sur **tout le contenu et la publication**, après une seule configuration initiale du compte (≈ 1 h, ensemble). Les seules limites sont imposées par Meta (création de compte, tokens, pas de DM auto).

---

## 2. Stratégie éditoriale

### Positionnement
Le seul Word Connect qui fait **voyager dans la culture ivoirienne et africaine** : proverbes, cuisine, masques, légendes, 54 pays = 54 montagnes. Fierté culturelle + jeu de réflexion accessible.

### Cible
- **Cœur** : diaspora ivoirienne/ouest-africaine (France, Canada, USA, Belgique) + joueurs en Côte d'Ivoire (18-45 ans).
- **Élargissement** : amateurs de jeux de mots, curieux de culture africaine, lusophones/anglophones plus tard.

### Ton
Chaleureux, fier, malicieux. Mélange de français standard et de touches ivoiriennes (« On est ensemble », « Enjaillé »). Pédagogue sans être scolaire.

### 5 piliers de contenu
1. **Devinette du jour** — une énigme culturelle (cuisine, masque, proverbe) → engagement en commentaires, réponse le lendemain.
2. **Le saviez-vous ?** — anecdote culturelle liée à un pays/montagne du jeu (carrousel illustré).
3. **Coulisses du jeu** — gameplay, audio balafon/kora, nouvelles montagnes, dev diary (storytelling indie).
4. **Défi communauté** — mode 1v1, classements, « bats ton ami », UGC/scores partagés.
5. **Fierté & patrimoine** — proverbes inspirants, hommages aux pays africains, dates culturelles.

### Formats & rythme (lancement)
- **Reels** : 3 / semaine (gameplay, devinette animée, proverbe).
- **Carrousels** : 2 / semaine (saviez-vous, anecdotes pays).
- **Stories** : quotidien (devinette, sondages, countdown sorties).
- **Post simple** : 1 / semaine (proverbe visuel).

Rythme conseillé : **5-7 posts/semaine** + stories quotidiennes. Heures fortes diaspora : 12 h-14 h et 19 h-22 h (heure locale cible).

### Hashtags (rotation par lots de ~12)
`#SagesseIvoirienne #CôteDIvoire #225 #Afrique #ProverbeAfricain #JeuDeMots #WordGame #CultureAfricaine #Abidjan #DiasporaAfricaine #IndieGame #JeuMobile #Kilimandjaro #FierteAfricaine #BalafonKora`

### KPIs à suivre
Taux d'engagement, reach, sauvegardes (clé pour les carrousels « saviez-vous »), clics vers le store à partir du lancement, abonnés/semaine.

---

## 3. Setup technique — auto total via API Meta

### Pré-requis (config unique, ensemble)
1. **Compte Instagram Professionnel** (Business ou Creator) — gratuit, dans les réglages du compte.
2. **Page Facebook** liée au compte Instagram (obligatoire pour l'API).
3. **App Meta Developers** sur `developers.facebook.com` → produit **Instagram Graph API**.
4. **Token d'accès longue durée** (60 j, renouvelable automatiquement par script) + **App Review** Meta pour les permissions de publication (`instagram_content_publish`).

### Comment ça publie (Instagram Content Publishing API)
Publication en 2 appels : (1) créer un *media container* à partir d'une URL d'image/vidéo + légende, (2) publier le container. Les images doivent être hébergées sur une URL publique (Firebase Storage du projet convient parfaitement — déjà dans la stack).

### Boucle d'autopilote (tâche planifiée)
1. Claude génère le lot de la semaine (visuels + légendes + hashtags) selon le calendrier.
2. Visuels uploadés sur Firebase Storage → URL publiques.
3. Tâche planifiée quotidienne : publie le post du jour via l'API Meta à l'heure forte.
4. Rapport hebdo : Claude résume performances + propose ajustements.

### Limites Meta à connaître
- Quota : **25 publications / 24 h** par compte (large pour notre rythme).
- Carrousels et Reels supportés ; les **stories** via API sont limitées selon le type de compte.
- **Pas de DM automatisés** (interdit). Les réponses aux commentaires peuvent être semi-assistées.
- L'App Review Meta prend quelques jours → à lancer tôt.

### Alternative si tu veux démarrer plus vite
Un planificateur tiers (Buffer / Later / Metricool) : je prépare tout, tu colles dans l'outil ou il publie via sa propre connexion. Moins « pur autopilote » mais opérationnel en 30 min, sans App Review.

---

## 4. Prochaines étapes proposées

1. **Toi** : passer le compte en Business + créer/lier la Page Facebook (je te guide écran par écran).
2. **Ensemble** : créer l'app Meta + générer le token (≈ 1 h).
3. **Moi** : produire le premier lot de 2 semaines de contenu (visuels + légendes) pour validation.
4. **Moi** : mettre en place la tâche planifiée de publication + le rapport hebdo.

> Note : le lancement du jeu étant prévu vers S10, on peut démarrer le compte **dès maintenant en phase teasing** (coulisses, devinettes, compte à rebours) pour bâtir une communauté avant la sortie.
