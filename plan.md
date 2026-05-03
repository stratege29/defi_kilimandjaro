# KILIMANDJARO — Plan de développement complet

> Word Connect culturel africain (Sagesse Ivoirienne) avec mode Défi 1v1 temps réel.
> Stack : Flutter 3.27 + Firebase. Bundle : `com.ultimesgriots.kilimandjaro`.
> Cible : Launch v1.0 SOLO en S10, v2.0 SOLO+DÉFI en S14.

---

## 0. Vue d'ensemble

### Modes de jeu
- **Solo (cœur)** — 4 mondes, carte d'Afrique 54 pays, montagnes infinies par pays. **100 % offline.**
- **Défi 1v1 temps réel (signature)** — duel synchrone, le plus rapide à former le mot gagne. Online.

### Différenciation
1. **Culture authentique ivoirienne** — devinettes validées par expert universitaire, proverbes, illustrations SVG, audio synthétisé balafon/kora/tam-tam.
2. **Multijoueur 1v1 instantané** — matchmaking ELO < 5s, sub-200ms latence Realtime DB.
3. **Progression géographique** — 54 pays africains, 6 zones par montagne, niveaux infinis.
4. **Audio procédural** — pas de fichiers WAV, génération Web Audio API → build < 25 MB.

---

## 1. Architecture technique

### Frontend (Flutter)
- Flutter 3.27+ / Dart 3.6+
- Clean Architecture (data / domain / presentation)
- State : `flutter_riverpod` 2.6
- Routing : `go_router` 14 (deep links défis)
- Animations : Flutter built-in + `rive`
- Audio : `just_audio` + `flutter_soloud` (synthèse procédurale)
- Storage : `shared_preferences` + `isar` (cache niveaux)
- Localisation : `easy_localization` (FR-CI / FR-FR / EN slot)

### Backend (Firebase)
- **Auth** : anonyme + Google + Apple Sign In
- **Firestore** : profils, progression, économie Coins, classements
- **Realtime DB** : duels 1v1 (latence ~80 ms)
- **Cloud Functions v2** (Node 20 + TypeScript) : matchmaking ELO, validation mots, anti-cheat, attribution coins
- **App Check** : DeviceCheck iOS / Play Integrity Android
- **Remote Config** : équilibrage économie sans store update
- **FCM** : notifications défis + streak
- **Storage** : SVG illustrations lazy-load
- **Analytics + Crashlytics + Performance Monitoring**

### Monétisation
- **IAP** (`in_app_purchase`) : packs Coins (49/199/499/1499/4999), No-Ads 4,99 €
- **AdMob** (`google_mobile_ads`) : rewarded video pour indices, interstitiel 1/3 défaites, **jamais pendant duel**
- **Battle Pass** mensuel 4,99 € (en v1.1)

### Outils dev
- CI/CD : Codemagic (free 500 min/mois)
- Tests : `flutter_test` + `mockito` + `integration_test`
- Lint : `very_good_analysis`
- Beta : Firebase App Distribution + TestFlight
- Crash : Firebase Crashlytics + Sentry
- Versioning : Git + GitHub (`main` protégée, `dev` integration, `feature/*`)

---

## 2. Roadmap 14 semaines

### Phase 0 — Setup & Foundation (S1)
- [ ] `flutter create` projet `defi_kilimandjaro` org `com.ultimesgriots`
- [ ] Setup Firebase projects `kilimandjaro-dev` + `kilimandjaro-prod`
- [ ] `flutterfire configure` pour iOS + Android
- [ ] Structure Clean Architecture (`lib/core`, `data`, `domain`, `presentation`)
- [ ] Riverpod + go_router + freezed setup
- [ ] Theme Flutter depuis palette maquette p.2 (couleurs + Bebas Neue / Playfair / Crimson Pro)
- [ ] CI Codemagic build matrix iOS/Android
- [ ] App Check enrôlement debug
- [ ] Splash screen écran 01 fonctionnel

### Phase 1 — Solo Gameplay Core (S2-S4)
- [ ] **Écran 02 Hub des Mondes** — 4 cartes mondes verticales, barre progression, verrous
- [ ] **Écran 03 Écran de Jeu** (cœur) :
  - [ ] `CircularGrid` CustomPainter — tuiles bois disposées circulairement
  - [ ] `GoldenPath` CustomPainter — chemin doré tracé au glissement (Canvas API equivalent)
  - [ ] Drag-to-connect via `Listener` + `setPointerCapture` equivalent
  - [ ] Timer tam-tam 30 s avec accélération <15s / <8s
  - [ ] Carte devinette + avatar griot
  - [ ] Cellules réponse 42×42 px, flash vert sur validation
  - [ ] Boutons Indice (-20 coins) / Effacer / Valider (auto si len === answer.length)
- [ ] **Écran 04 Victoire** — overlay sombre, mot trouvé en or, illustration SVG, proverbe, +coins, 12 particules emoji
- [ ] **Écran 05 Échec** — feedback non-punitif, mot révélé en rouge, proverbe consolation
- [ ] **Audio synthétique** : balafon (sélection), kora (indice), tam-tam (timer), djembé (erreur), fanfare griot (victoire)
- [ ] Tests widget grille + drag detection
- [ ] **100 devinettes initiales** monde "Village des Or"

### Phase 2 — Progression & Contenu (S5-S6)
- [ ] **Écran 06 Carte d'Afrique** — Canvas 2D, 54 points-pays, halo or pays disponibles, drapeaux emoji, légende
- [ ] **Écran 07 Montagne** — fond peint (ciel étoilé + neige), niveaux zigzag, 6 zones nommées (Base → Sommet mythique), nuages pulsants niveaux cachés
- [ ] Génération procédurale niveaux infinis par pays
- [ ] Économie Coins de Sagesse — gain victoire + bonus vitesse + coût indice
- [ ] **Contenu : 200 devinettes** réparties sur 4 mondes + monde "Côte d'Ivoire" (Mont Nimba etc.)
- [ ] Cache local devinettes (`isar`) + override Remote Config

### Phase 3 — Profil & Rétention (S7)
- [ ] **Écran 08 Profil** — avatar bois+or, 4 stats (Niveaux/Coins/Pays/Streak), pays explorés (chips drapeaux), titres honorifiques 4 paliers
- [ ] Système titres : Oreille du Village → Gardien de la Parole → Griot du Feu → Ancêtre Vivant
- [ ] FCM rappels quotidiens (notification "Le griot t'attend !")
- [ ] Streak quotidien + récompense escalier
- [ ] Toggle son + toggle timer + bouton réinitialisation (confirm dialog)

### Phase 4 — Monétisation (S8)
- [ ] IAP packs Coins (test sandbox iOS + license tester Android)
- [ ] AdMob — rewarded video "+50 coins", interstitiel après 3 échecs
- [ ] No-Ads purchase 4,99 € (entitlement persistant)
- [ ] Remote Config : drop rates, prix indices, A/B onboarding
- [ ] Privacy Manifest iOS + Data Safety Android

### Phase 5 — MVP Solo Soumission (S9)
- [ ] Polish accessibilité (zones tactiles 44×44 px min)
- [ ] Performance : 60 fps sur iPhone SE (375 px) + Galaxy A10
- [ ] Build size < 30 MB après obfuscation Dart
- [ ] Beta TestFlight + APK partagés WhatsApp testeurs Abidjan
- [ ] Tests E2E intégration golden path
- [ ] Crash-free rate > 99,5 %
- [ ] App Store Connect + Play Console submission
- [ ] Mentions légales + CGU + politique confidentialité (RGPD)
- [ ] ASO : keywords FR + screenshots français + vidéo aperçu

### 🚀 Launch v1.0 SOLO (S10)
- App Store + Play Store, jeu solo complet 100 % offline.

### Phase 6 — Mode Défi 1v1 (S11-S13)
- [ ] **Cloud Functions** :
  - [ ] `requestMatch()` — file d'attente Realtime DB par tranche ELO
  - [ ] `endMatch()` — calcul ELO, attribution coins, écriture Firestore
  - [ ] `validateWord()` — reconstruction serveur du mot depuis indices client
- [ ] **Realtime DB schema** :
  ```
  /lobby/{rank}/{uid} : {ts, mmr}
  /matches/{matchId}/word_seed : <int>
  /matches/{matchId}/players/{uid} : {progress, indices_traced[], finished_at}
  ```
- [ ] Anti-cheat : génération mot 100 % serveur, rate limit 1 match / 3 s, détection patterns
- [ ] Mode dégradé : bot IA local si pas de réseau (délais réalistes selon ELO)
- [ ] Écran lobby (recherche adversaire, animation tam-tam)
- [ ] Écran duel (split UI : ma grille + barre progression adversaire en haut)
- [ ] Écran résultat duel (victoire/défaite + ELO gagné/perdu)
- [ ] Bouton "Défi" optionnel dans Hub (auth requise)

### Phase 7 — Social & Viral (S14)
- [ ] Défi asynchrone via lien partageable (`go_router` deep link `/duel/{matchId}`)
- [ ] Partage WhatsApp avec image résultat générée
- [ ] Classement amis (Firestore + Auth Google contacts)
- [ ] Push FCM "Ton ami X t'a défié !"
- [ ] Mode rematch après duel
- [ ] Tournoi quotidien (top 16 brackets) — feature flag Remote Config

### 🚀 Launch v2.0 SOLO + DÉFI (Fin S14)
- Update majeure App Store/Play Store + campagne ASO + influenceurs Abidjan/Dakar.

---

## 3. Critical files / décisions à locker S1

1. **State management** → Riverpod (testabilité, écosystème 2026)
2. **DB duel** → Realtime DB (latence + coût)
3. **Génération mots** → 100 % serveur Cloud Function
4. **Audio** → synthèse pure (gain build size)
5. **Premier fichier à designer** : `lib/presentation/game/widgets/circular_grid.dart`
6. **Cache devinettes** → JSON chiffré bundlé + override Remote Config

---

## 4. Structure projet

```
defi_kilimandjaro/
├── lib/
│   ├── core/              # constants, theme, errors, utils, i18n
│   ├── data/              # repositories Firebase, models freezed, datasources
│   ├── domain/            # entities, use cases, repositories interfaces
│   ├── presentation/
│   │   ├── splash/        # 01
│   │   ├── hub/           # 02
│   │   ├── game/          # 03 — cœur, CircularGrid + GoldenPath
│   │   ├── result/        # 04 + 05
│   │   ├── map/           # 06 — carte 54 pays
│   │   ├── mountain/      # 07 — montagne par pays
│   │   ├── profile/       # 08
│   │   └── duel/          # mode multijoueur
│   ├── audio/             # synthèse procédurale balafon/kora/tam-tam
│   └── main.dart
├── functions/             # Cloud Functions TypeScript
│   └── src/
│       ├── matchmaking.ts
│       ├── validateWord.ts
│       └── endMatch.ts
├── assets/
│   ├── svg/               # illustrations sujets (lazy load)
│   ├── data/devinettes/   # JSON par monde (chiffré prod)
│   └── i18n/              # fr-CI.json, fr-FR.json, en.json
├── test/
│   ├── unit/
│   ├── widget/
│   └── integration/
├── .claude/               # agents, skills, settings.json, hooks
├── ios/ android/          # configs natives
├── CLAUDE.md
├── plan.md
└── pubspec.yaml
```

---

## 5. Configuration Claude Code optimisée

### Token efficiency
- Modèle par défaut : Sonnet (60 % moins cher qu'Opus)
- Subagents : Haiku (`CLAUDE_CODE_SUBAGENT_MODEL=haiku`)
- `MAX_THINKING_TOKENS=10000`
- CLAUDE.md sous 500 tokens
- `.claudeignore` strict (build/, .dart_tool/, ios/Pods/, etc.)

### Hooks deterministes (`.claude/settings.json`)
- **PostToolUse Edit/Write** : `dart format` automatique sur fichiers `.dart`
- **PostToolUse Edit/Write** : `flutter analyze` sur `lib/`
- **PreToolUse Bash** : bloquer `rm -rf` et secrets dans commits
- **UserPromptSubmit** : injection auto contexte palette/typo si message contient "UI" ou "design"

### Agents custom projet
- `firebase-multiplayer` — duel 1v1, Realtime DB, Cloud Functions, anti-cheat
- `devinette-curator` — gestion contenu culturel, validation linguistique, format JSON
- + agents existants : `flutter-architect`, `flutter-ui-expert`, `Plan`, `Explore`

### Skills custom
- `/add-devinette` — workflow ajout devinette (validation format + tests)
- `/test-duel` — lance simulation duel 2 devices
- `/sync-firebase` — déploie functions + rules + indexes
- `/release-build` — build iOS + Android signés + upload stores

---

## 6. Vérification & KPIs

### Tests pré-release
- [ ] `flutter test` coverage > 70 % sur `domain/` et `data/`
- [ ] `flutter test integration_test/` golden path
- [ ] Test multijoueur 2 devices simulation perte réseau
- [ ] Offline : tous écrans solo OK sans réseau
- [ ] Accessibilité VoiceOver iOS + TalkBack Android
- [ ] Build size < 30 MB après obfuscation
- [ ] Cold start < 2 s sur iPhone SE / Galaxy A10

### KPIs métier
- D1 retention > 40 %
- D7 retention > 20 %
- Avg session > 8 min
- Duel completion rate > 75 %
- ARPDAU > 0,05 € après S14
- Crash-free users > 99,5 %

### Pre-launch checklist
- [ ] App Privacy Manifest iOS
- [ ] Google Play Data Safety form
- [ ] CGU + politique confidentialité RGPD
- [ ] Modération anti-triche active J1
- [ ] Onboarding < 3 écrans skippable
- [ ] Première victoire < 90 s
- [ ] Localisation FR-FR + FR-CI validée locuteur natif

---

## 7. Budget MVP

| Poste | Coût |
|---|---|
| Apple Developer | 99 $/an |
| Google Play | 25 $ one-shot |
| Firebase Spark | 0 € (jusqu'à 50k MAU) |
| Codemagic | 0 € (500 min/mois) |
| Domaine | ~15 €/an |
| Illustrations SVG (50 sujets) | ~500 € |
| 500 devinettes validées expert | 1500-3000 € |
| **Total atteindre stores** | **~2500 €** |

---

## 8. Prochaines actions immédiates

1. ✅ Créer ce plan.md + CLAUDE.md + .claude/ config
2. ⏳ User crée comptes Apple Developer + Google Play + Firebase
3. ⏳ `flutter create defi_kilimandjaro --org com.ultimesgriots --platforms ios,android`
4. ⏳ Lancer `flutter-architect` sur Phase 0 (Clean Architecture + Firebase)
5. ⏳ Lancer en parallèle `flutter-ui-expert` sur theme.dart depuis maquette
6. ⏳ Premier merge `main` avec splash screen J3

---

*Document vivant — mis à jour à chaque fin de phase. Voir `CLAUDE.md` pour les conventions de code et `.claude/agents/` pour l'équipe spécialisée.*
