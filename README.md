# Kilimandjaro — Sagesse Ivoirienne

> Word Connect culturel africain (Côte d'Ivoire) avec mode Défi 1v1 temps réel.

[![Status](https://img.shields.io/badge/status-pre--alpha-orange)]()
[![Flutter](https://img.shields.io/badge/Flutter-3.27%2B-02569B?logo=flutter)]()
[![Firebase](https://img.shields.io/badge/Firebase-FFCA28?logo=firebase&logoColor=black)]()

## 🎯 Concept

Un Word Connect inspiré de "Mots Croisés" (App Store), enrichi de :
- Devinettes culturelles ivoiriennes (cuisine, masques, proverbes, légendes)
- Carte d'Afrique 54 pays — chaque pays = une montagne à gravir
- Audio synthétisé balafon / kora / tam-tam (Web Audio API portée Flutter)
- **Signature** : Défi 1v1 temps réel avec matchmaking ELO

## 📁 Structure

| Fichier | Rôle |
|---|---|
| [`plan.md`](./plan.md) | Plan de développement complet 14 semaines |
| [`CLAUDE.md`](./CLAUDE.md) | Conventions et règles pour Claude Code |
| [`docs/maquette.pdf`](./docs/maquette.pdf) | Maquette UI/UX 13 pages (référence visuelle) |
| `.claude/` | Configuration Claude Code : agents, skills, hooks, permissions |
| `lib/` | Code Flutter (Clean Architecture) — *à créer en S1* |
| `functions/` | Cloud Functions TypeScript — *à créer en S11* |
| `assets/data/devinettes/` | Contenu culturel JSON — *à curer en S2-S6* |

## 🚀 Démarrage

```bash
# Installer Flutter (si ce n'est pas déjà fait)
fvm install 3.27.0
fvm use 3.27.0

# Initialiser le projet (Phase 0, S1)
flutter create . --org com.ultimesgriots --project-name defi_kilimandjaro --platforms ios,android

# Configurer Firebase
flutterfire configure --project=kilimandjaro-dev

# Lancer en debug
flutter run --dart-define=FIREBASE_PROJECT=kilimandjaro-dev
```

## 🛠️ Stack technique

- **Frontend** : Flutter 3.27+, Dart 3.6+, Riverpod, go_router, freezed
- **Backend** : Firebase (Auth, Firestore, Realtime DB, Cloud Functions v2 TS, FCM)
- **Audio** : `flutter_soloud` (synthèse procédurale, zéro fichier audio bundlé)
- **Tests** : `flutter_test`, `mockito`, `integration_test`
- **CI/CD** : Codemagic
- **Monétisation** : `in_app_purchase` + AdMob

## 🤖 Claude Code — comment travailler avec ce projet

Le dossier `.claude/` contient :
- **`settings.json`** : permissions allowlist (flutter/dart/firebase/git), hooks `dart format` + `flutter analyze` automatiques, env optimisé tokens (Sonnet par défaut, Haiku pour subagents)
- **`agents/`** : agents projet spécialisés
  - `firebase-multiplayer` — pour le mode Défi 1v1
  - `devinette-curator` — pour le contenu culturel
  - `audio-synth` — pour la synthèse audio
- **`skills/`** : workflows réutilisables
  - `/add-devinette` — ajouter une devinette validée
  - `/sync-firebase` — déployer le backend
  - `/release-build` — produire les artefacts iOS/Android
  - `/new-screen` — scaffolder un écran Flutter

Modèles utilisés :
- Sonnet : tâches standard (60 % moins cher qu'Opus)
- Haiku : exploration et lecture (CLAUDE_CODE_SUBAGENT_MODEL=haiku)
- Opus : architecture critique et debug subtil (sur demande explicite)

## 📜 Licence

Propriétaire — Sagesse Ivoirienne / Ultimes Griots. Document confidentiel.

## 🌍 Contact

Studio : Ultimes Griots
Email : arnaudkossea@gmail.com
