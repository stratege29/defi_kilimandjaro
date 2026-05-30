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
- [ ] **À décider (produit/nav)** : relocaliser packs/news/stats vers des onglets dédiés.
      Conservés sur l'accueil pour l'instant — ce sont des **surfaces de monétisation/engagement**,
      les retirer sans onglet de remplacement nuirait à la découverte. Décision nav requise.

**✅ Phase 2 (cœur) terminée** (commit à faire). Reste : décision de relocalisation des blocs secondaires.

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
      **TODO(presence)** : compteur "N en ligne" — pas de noeud RTDB `/lobby/stats/online` exposé.
      **TODO(history)** : historique duels — pas de collection Firestore `duel_history`.

## Phase 6 — Popups / overlays
- [ ] `result/victory_view.dart`, `failure_view.dart`, `mountain_conquest_view.dart`,
      `home/widgets/daily_streak_dialog.dart` : cartes restylées.
- [ ] **Vraies mascottes griot** (`griot_victory`/`griot_sad`) au lieu de placeholders.
- [ ] Particules emoji → `fx/particle_gold`, `confetti_kente`.

## Phase 7 — Boutique / Classement / Profil
- [ ] `shop_view.dart` : **vraies illustrations** (`coins_s..mega`, `no_ads`) en grille + offre bienvenue.
- [ ] `leaderboard_view.dart` : onglets + mon rang + lignes.
- [ ] `profile_view.dart` : hero + altitude ELO + grille stats + sections.

## Phase 8 — Chasse aux emoji
- [ ] `grep` global emoji dans `lib/` ; drapeaux, 🥁 lobby, 🌍 duel entry, particules → vecteurs/assets.

## Phase 9 — QA / perf / a11y / tests
- [ ] `flutter analyze` 0 warning ; aucun hex en dur ; strings via `easy_localization`.
- [ ] ⚠️ Perf iOS 26 : éviter `MaskFilter.blur`, limiter `BackdropFilter`, `RepaintBoundary` sur
      radar/VS/parallaxe, animations en `AnimationController` (jamais `setState`).
- [ ] Tests widget des nouveaux composants ; mettre à jour les tests cassés par le re-skin.

---

## Séquencement
`0 → 1 → 3 → 2 → 4 → 5 → 6 → 7 → 8 → 9`

## Délégation agents
- Phases 0–1 : `flutter-architect`.
- Écrans/anim : `flutter-ui-expert`.
- Défi temps réel : `firebase-multiplayer`.
