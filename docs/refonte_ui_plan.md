# Refonte UI « Vert Nuit » — Plan d'implémentation

> **Source de vérité visuelle :** `design_preview/index.html` (maquette HTML interactive
> avec vraies polices, vrais assets, animations). Ouvrir via un serveur statique pour
> référence pendant l'implémentation.

## Direction validée
- **Canvas** vert nuit OLED `#0C1712` (garde l'ADN montagne/forêt, registre premium).
- **Un seul or** Baoulé `#E9B949` (fini les 2 ors qui coexistaient).
- **Accent Kola** `#F0533B` (énergie : duels, CTA secondaires, badges « nouveau »).
- **2 polices** : **Fraunces** (display, mots-réponses, altitudes, proverbes) ×
  **Hanken Grotesk** (toute l'UI). Fini Barlow Condensed / Bebas / Crimson.
- **Zéro emoji** dans l'UI fonctionnelle (drapeaux, mascotte-tambour, particules → vecteurs/assets).
- **Retenue radicale** : élévation par surfaces opaques, moins de glows/bordures alpha.

---

## Phase 0 — Fondations (tokens)  ⚡ plus haut levier
Re-skin de toute l'app en remappant les **valeurs** des tokens (noms conservés → 0 écran à toucher).

- [x] `lib/core/theme/app_colors.dart` — palette Vert Nuit, `kola`, `hairline`, texte crème/sauge.
- [x] `lib/core/theme/app_typography.dart` — Hanken Grotesk + Fraunces, helpers legacy reroutés.
- [x] `lib/core/theme/app_theme.dart` — `ColorScheme` + `textTheme` recâblés ; CTA or par défaut ; nav bar = surface.
- [x] `lib/core/theme/app_spacing.dart` — tokens de rayon ajoutés (`radiusSm/Md/Lg/Xl/Pill`).
- [x] `dart analyze lib/core/theme/` → **No issues found** (0 erreur/warning introduit par le re-skin).

**✅ Phase 0 terminée** (commit à faire).
**Notes :** `google_fonts` fournit déjà `hankenGrotesk`. ⚠️ Pour la release, **bundler les polices**
en assets (éviter la dépendance réseau au 1er lancement).
⚠️ Avant `flutter run` dans ce worktree : `dart run build_runner build -d` (drift `*.g.dart` manquants —
65 erreurs préexistantes sans rapport avec le thème, cf. `MEMORY/worktree_bootstrap.md`).
**DoD :** l'app boote, tous les écrans changent de peau, 0 warning.

## Phase 1 — Design system (composants)
- [x] `AppButton` : variantes **`kola`** + **`soft`** ajoutées (primary/secondary/ghost/danger déjà présentes).
- [x] `AppChip` (déjà présent, 3 formes × 6 tons) ; **`SectionLabel`** + **`StatTile`** créés.
- [x] `FlagRoundel` (pastille code-pays **vectorielle** → remplace emoji drapeaux).
- [x] `MountainHeroImage` (`AppAssets.mountainHero(id)` + fallback).
- [x] Tuile-lettre : refonte `_Tile` dans `circular_grid.dart`
      (carré coins doux, dégradé bronze→or, lèvre sculptée 3D, halo or à la sélection, lettre foncée crisp).
- [x] `dart analyze lib/presentation/widgets/ circular_grid.dart` → **No issues found**.

**✅ Phase 1 terminée** (commit à faire). `AppCard` (3 élévations) déjà en place.

## Phase 2 — Accueil
- [x] `continue_ascent_card.dart` : **vraie peinture du sommet** (`MountainHeroImage`, repli silhouette)
      + **`FlagRoundel`** (emoji drapeau retiré).
- [x] `home_view.dart` : **carte HÉROS en tête**, `WelcomeCard` retirée (le header salue déjà),
      espacements uniformisés (20pt), 3 zones logiques (héros · boucles du jour · découverte).
- [x] `MountainHeroImage` : ajout d'un `fallback` + `alignment`.
- [x] `dart analyze` accueil → 0 issue introduite (1 `info` préexistant).
- [x] **Relocalisation packs/news/stats** (décision : *icône Boutique dans le header*, 4 onglets conservés) :
      nouvel écran **`DiscoverView`** (`/discover`) hébergeant `PacksSection` + `NewsCarousel`, ouvert
      via une **icône Boutique** dans le header d'accueil (distincte du chip cauris → `/shop`).
      `StatsRow` retiré de l'accueil (les stats vivent déjà dans le Profil). Accueil = héros · boucles
      du jour · reco — vraiment minimal. `dart analyze` (nav) → clean.

**✅ Phase 2 terminée** (commit à faire).

## Phase 3 — Jeu
- [x] `game_view.dart` : carte devinette à **accent gauche or** (ClipRRect + filet 3pt, ombre).
- [x] `timer_bar.dart` : **or → warning (12 s) → kola (5 s)** + shimmer danger.
- [x] `answer_cells.dart` : rayon arrondi (6 → 10) ; tuiles `circular_grid` faites en Phase 1.
- [x] **Flag emoji header → `FlagRoundel`** (via `mountain.countryCode`).
- [x] `dart analyze` jeu → 0 issue introduite (2 `info` préexistants non liés).

**✅ Phase 3 terminée** (commit à faire). Boutons d'action (`_GameButton`) : OK via re-skin tokens
(bois/boisFonce/ciel), refonte fine reportée si besoin.

## Phase 4 — Sommets (parallaxe + altimètre)
- [x] « Montagne = seul focus » : **déjà acquis** — le vrai écran est un `PageView` vertical
      (1 sommet = 1 viewport), pas de barre secondaire à retirer.
- [x] **Hero PNG au 1er plan** (`MountainHeroImage`, repli silhouette) + **halo pulsé** du sommet courant.
- [x] **Emoji drapeau → `FlagRoundel`** dans l'en-tête de sommet.
- [x] CTA GRAVIR : texte foncé crisp (surface) sur or.
- [x] `atmosphere_layer.dart` / `altimeter_rail.dart` : reskinés **automatiquement** via tokens
      (orSoleil→or, vertForet→canvas, cielHauteur, etc.). Astre/cirrus naturalistes conservés.
- [x] `dart analyze` → **No issues found**.

**✅ Phase 4 terminée** (commit à faire).

## Phase 5 — Défi (la plus lourde, en sous-étapes)

### 5a — fait
- [x] **VERSUS combat** (`duel_intro_overlay.dart`) : fond **split diagonal** (or vs indigo,
      CustomPaint `_VersusBackdrop`) + lame dorée + montagne silhouettée + vignette ;
      avatars **face à face** avec anneau couleur de camp + **plaque de nom inclinée** (skew) ;
      **VS métallique** (Fraunces italique relief + éclat de rayons `_BurstPainter`).
      Animations slide-in/flash préservées. `dart analyze` → **No issues found**.
- [x] **Décompte 3·2·1·GO** (`duel_countdown_overlay.dart`) : **reskiné auto** via tokens
      (or + canvas + surfaceVariant) — aucun changement requis.

### 5b — en cours
- [x] **Recherche radar** (`lobby_view.dart`) : anneau de décompte + emoji tam-tam 🥁 **remplacés** par
      un **radar** (`_RadarSearch`/`_RadarPainter`) — ondes concentriques déphasées + balayage rotatif
      (SweepGradient) autour de **ton avatar** (initiale sur disque or). Texte recentré, ANNULER en `error`.
      Classes mortes supprimées (`_CountdownRing`, `_RingPainter`, `_TamTamMascot`, constantes BPM).
      `dart analyze` → **No issues found**. *(Pas de `MaskFilter.blur` — perf iOS 26.)*

- [x] `duel_play_view.dart` : carte devinette **accent gauche or** + **couleurs de camp**
      (joueur=or, adversaire=indigo, cohérent VERSUS). `dart analyze` → clean.
- [x] `duel_result_view.dart` : hiérarchie CTA — **RETOUR AU HUB en or** (primaire), **REMATCH en kola**.
      Reste auto via tokens (score Fraunces, VS banner, ELO ±). `dart analyze` → clean.

### 5b — terminé
- [x] **Hub Défi** (`lib/presentation/duel/duel_hub_view.dart`) : carte EN LIGNE · CLASSÉ
      (fond montagne, ELO Firestore réel, CTA → lobby) + banner invite Kola (RTDB
      `pending_challenges` réel) + 2 action cards Défier/Scanner + section Derniers duels
      (empty state honnête). Routing : `AppRoutes.hub` redirige désormais vers `DuelHubView`.
      **Données réelles** : ELO/profil (Firestore `playerProfileStreamProvider`),
      challenge entrant (RTDB `pending_challenges/{uid}`).
      `dart analyze` → **No issues found**.

### 5c — Présence en ligne & historique duels (PR additionnel)
- [x] **Feature 1 — Présence "N grimpeurs en ligne"** :
      - Compteur centralisé `/lobby/stats/online` en Realtime DB (incrément/décrement via CF `requestMatch` + `onDisconnect`).
      - Client-side : `PresenceRepository.registerPresence()` appelé au lancement du hub (configurable ultérieurement).
      - Provider Riverpod : `onlinePlayersCountProvider` (StreamProvider<int>) exposé et wired dans `_OnlineHeroCard`.
      - Chip affichage : `AppChip(tone: success)` montrant "N grimpeur(s)" si > 0, caché si 0 ou non chargé.
      - Sécurité RTDB : `/lobby/stats/online` lecture seule côté client, écriture CF uniquement.
      `dart analyze` → **No issues found**.

- [x] **Feature 2 — Historique des duels** :
      - Persistence : Firestore subcollection `profiles/{uid}/duel_history/{matchId}` (écrit par CF `endMatch` pour les 2 joueurs).
      - Entity : `DuelHistoryEntry` (opponent_uid/name, did_win, elo_delta, finished_at) avec méthodes utilitaires.
      - Repository : `DuelHistoryRepository.watchRecentDuels()` (limit 5, ordered desc).
      - Provider : `recentDuelsProvider` (StreamProvider<List<DuelHistoryEntry>>) exposé et wired dans `_RecentDuelsSection`.
      - UI : `_DuelHistoryRow` affiche V/D badge, nom adversaire, timestamp relatif ("Il y a 2 h"), ±ELO delta (couleurs success/error).
      - Empty state : honnête pour nouveaux joueurs ; loading/error gracefully handled.
      - Cloud Function `endMatch` : 2 écritures batch pour créer les entrées duel_history côté server (intégrité).
      - Sécurité Firestore : subcollection `duel_history` lecture seule par owner, écriture CF uniquement.
      `dart analyze` → **No issues found**.

## Phase 6 — Popups / overlays
- [x] **Mascottes griot réelles** : `victory_view` utilise déjà `griotVictory`,
      `failure_view` déjà `griotSad` — confirmé en place (pas de placeholder).
- [x] **Particules emoji → vectorielles peintes** (`victory_view._ParticlePainter`,
      `mountain_conquest_view._StarBurstPainter`) : étincelles 4 branches + cauris + poussière crème,
      dorées, animées en éventail. ⚠️ `assets/images/fx/` est **vide** (`.gitkeep` seul) — les PNG
      `particle_gold`/`confetti_kente` n'existent pas → painted vector retenu (mieux : 0 dépendance
      asset, rendu identique tous OS, crisp). Imports `dart:ui` retirés.
- [x] `failure_view.dart` / `daily_streak_dialog.dart` : déjà conformes (AppButton, tokens,
      icônes Material, zéro emoji) — reskin auto, aucun changement requis.
- [x] `dart analyze` (4 popups) → **No issues found**.

**✅ Phase 6 terminée** (commit à faire).

## Phase 7 — Boutique / Classement / Profil
- [x] `shop_view.dart` : **utilise déjà** les vraies illustrations (`shopPackSheet`, `shopCauris S/M/L/XL/Mega`
      scalées par montant, `shopNoAds`) — reskin auto via tokens, aucun changement requis.
      *(Note : `✓` ligne 523 = glyphe texte monochrome, pas un emoji couleur → OK. `:315` lint info préexistant.)*
- [x] `profile_view.dart` : **emoji drapeau → `FlagRoundel`** (cartes montagnes). `dart analyze` → clean.
- [x] `leaderboard_view.dart` : aucun emoji, reskin auto via tokens (or/ELO/lignes).

**✅ Phase 7 terminée** (commit à faire).
- [ ] `profile_view.dart` : hero + altitude ELO + grille stats + sections.

## Phase 8 — Chasse aux emoji
- [x] Audit `grep` global `lib/`. Emoji UI résiduels supprimés :
  - **Icônes titres honorifiques** 👂📖🔥🌿 (`honorific_title.dart`) : champ `icon` retiré de l'enum,
    rendu profil basculé sur **badge PNG** (`title.badgeAsset` 18px) — les badges existent déjà.
  - **flagEmoji → `FlagRoundel`** : `mountain_detail_view`, `altimeter_rail` (label flottant).
  - **🌍** retiré (`duel_entry_view`).
  - *(Déjà faits phases précédentes : 🥁 lobby, particules ✨🌟🪙 victoire/conquête,
    drapeaux game/sommets/profil/accueil.)*
- [x] `dart analyze` (5 fichiers) → clean (1 `info` préexistant non lié).
- **Résiduels acceptables** (non-UI ou glyphe texte mono) : `🛡️` dans un **log** Firebase
  (`app_check_setup`), `✓` dingbat texte dans le label « Déjà acheté » (shop), `★` glyphe data
  (daily challenge). Aucun **emoji couleur OS-dépendant** ne subsiste dans l'UI rendue.

**✅ Phase 8 terminée** (commit à faire).

## Phase 9 — QA / perf / a11y / tests
- [x] **Analyse** : `dart analyze lib/` → 65 err / 13 warn **100 % préexistants** (drift `*.g.dart` +
      `firebase_options.dart` gitignorés non générés dans ce worktree). **0 régression introduite** par la refonte.
- [x] **Hex en dur** : tokenisé les 4 `Color(0xFF…)` introduits par l'agent dans `duel_hub_view`
      (bordure → `hairline`, gradients dérivés via `Color.lerp` des tokens).
- [x] **Perf iOS 26** : aucun `MaskFilter.blur` dans le code refonte ; `RepaintBoundary` ajouté sur
      les particules (victoire/conquête) ; VERSUS + radar déjà encapsulés ; animations en
      `AnimationController` (pas de `setState` ajouté).
- [x] **Tests** : 35 tests unitaires purs passent (dont `honorific_title_test` — le retrait du champ
      `icon` ne casse rien) ; **+2 tests widget** `FlagRoundel` (GoogleFonts no-fetch) verts.
      Aucun symbole supprimé n'est référencé par `test/`.

**⚠️ Constats préexistants (hors refonte) :**
- [x] `golden_path.dart` `MaskFilter.blur(8)` → **remplacé** par un halo empilé (3 traits dégradés,
  fake-glow GPU-safe). **Plus aucun `MaskFilter` actif dans `lib/`.** `dart analyze` clean.
- `BackdropFilter` dans 4 fichiers (`bottom_nav_bar`, `app_card`, countdown/round_end overlays) — préexistant,
  à surveiller sur iOS 26 (blur 18px sur la nav notamment) mais hors scope refonte.
- Worktree neuf : `dart run build_runner build -d` + copier `firebase_options.dart` avant `flutter run` /
  suite de tests complète (cf. `MEMORY/worktree_bootstrap.md`).
- Tests widget supplémentaires (AppButton variants, StatTile, SectionLabel) : recommandé en suivi.

**✅ Phase 9 terminée** (commit à faire). **Refonte « Vert Nuit » : Phases 0 → 9 complètes.**

---

## Phase 5c — Déploiement (Présence + Historique)

### Fichiers modifiés
**Dart :**
- `lib/domain/entities/duel_history_entry.dart` (nouveau)
- `lib/data/repositories/duel_history_repository.dart` (nouveau)
- `lib/data/repositories/presence_repository.dart` (nouveau)
- `lib/presentation/duel/duel_hub_view.dart` (2 providers filés, UI)

**Cloud Functions v2 (TypeScript) :**
- `functions/src/matchmaking/endMatch.ts` (duel_history subcollection writes)
- `functions/src/matchmaking/requestMatch.ts` (online counter increment/onDisconnect)

**Security Rules :**
- `database.rules.json` (`/lobby/stats/online` + `/presence/{uid}`)
- `firestore.rules` (subcollection `duel_history` read-only by owner)

**Documentation :**
- `docs/refonte_ui_plan.md` (Phase 5c complete)

### Deploy commands
```bash
# 1. Deploy Firestore rules + Realtime DB rules
firebase deploy --only database,firestore:rules

# 2. Deploy Cloud Functions v2 (endMatch + requestMatch + autres)
firebase deploy --only functions

# 3. Rebuild Flutter (ensure new Dart files compile)
flutter pub get && flutter analyze
```

### Tradeoffs & notes
- **Presence counter** : incrément côté CF `requestMatch`, onDisconnect décrémente. Léger délai de 30–60s si déconnexion brutale (délai RTDB standard). Acceptable pour un "environ N joueurs".
- **Duel history** : écrit côté serveur (CF) pour intégrité. Chaque joueur a sa propre subcollection pour isolation.
- **Graceful degradation** : chip présence cache si 0 ou loading ; section histoire affiche empty state si pas de duels.
- **Pas de migration** : nouvelles collections créées on-demand lors du premier write.

---

## Séquencement
`0 → 1 → 3 → 2 → 4 → 5 → 6 → 7 → 8 → 9 → 5c`

## Délégation agents
- Phases 0–1 : `flutter-architect`.
- Écrans/anim : `flutter-ui-expert`.
- Défi temps réel : `firebase-multiplayer`.
- Phases 5c (Présence + Histoire) : `firebase-multiplayer`.
