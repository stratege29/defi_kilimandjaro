# Kilimandjaro — Sagesse Ivoirienne

Word Connect culturel africain (Flutter + Firebase). Mode solo offline + Défi 1v1 temps réel.
Bundle: `com.ultimesgriots.kilimandjaro`. Voir `@plan.md` pour la roadmap complète.

## Stack
- **Frontend**: Flutter 3.27+, Dart 3.6+, Riverpod 2.6, go_router 14, freezed
- **Backend**: Firebase (Auth, Firestore, Realtime DB, Cloud Functions v2 TS, FCM, Remote Config, App Check)
- **Audio**: synthèse procédurale (just_audio + flutter_soloud), JAMAIS de fichiers WAV
- **Tests**: flutter_test + mockito + integration_test, coverage > 70% sur domain/data

## Architecture
Clean Architecture stricte: `lib/{core,data,domain,presentation,audio}/`. Chaque feature suit `presentation/<screen>/{view,widgets,controller}.dart`. Cloud Functions dans `functions/src/`.

## Conventions code
- Lint: `very_good_analysis` (zéro warning toléré)
- Naming: `snake_case` fichiers, `PascalCase` classes, `camelCase` méthodes
- Pas de `BuildContext` dans les controllers (Riverpod `Ref` only)
- Pas de `setState` — toujours providers
- Couleurs/typos uniquement via `lib/core/theme/` (jamais de hex en dur)
- Strings utilisateur uniquement via `easy_localization` (`'key'.tr()`)

## Règles strictes
- **JAMAIS** de secrets/clés API en clair (utiliser `--dart-define` ou Remote Config)
- **JAMAIS** de génération de mots côté client (anti-cheat: 100% Cloud Function)
- **JAMAIS** de pub pendant un duel temps réel
- **TOUJOURS** `flutter analyze` après modifs `lib/` (hook automatique)
- **TOUJOURS** validation serveur des achats IAP via Cloud Function

## Workflow
- Branche `main` protégée, PRs depuis `feature/*`
- Tests `flutter test` avant chaque PR
- Plan mode pour features > 3 fichiers
- `/clear` entre tâches non liées

## Agents projet
- `flutter-architect` — architecture, Firebase, Cloud Functions
- `flutter-ui-expert` — UI, animations, CustomPainter (grille circulaire)
- `firebase-multiplayer` — duel 1v1, Realtime DB, anti-cheat
- `devinette-curator` — contenu culturel ivoirien, validation
- `Plan` — features complexes
- `Explore` — recherche dans codebase grandissant

## Délégation contexte
Pour exploration codebase ou recherche multi-fichiers: **utiliser un subagent**, pas le contexte principal.

## Maquette de référence
Palette + typographies: voir `docs/maquette.pdf` p.2 (8 écrans documentés p.3-10).
