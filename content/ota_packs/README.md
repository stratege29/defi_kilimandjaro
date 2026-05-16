# OTA Packs

**Source des nouvelles questions distribuées via Firebase (OTA), pas bundlées dans l'app.**

## Architecture

Le contenu d'un pack distant (gz uploadé sur Cloud Storage) est constitué de :

```
starter/<packId>.json   (assets/data/devinettes/starter/, bundled, FROZEN)
  +
content/ota_packs/<packId>.json (ce dossier, non bundled, alimentation continue)
  =
build/seed_packs/<packId>/<packId>-vN.json.gz (artefact uploadé)
```

Le merge est fait par `tool/seed_content_packs.dart` :
- Si un même `id` existe dans starter ET ota_packs, **ota_packs gagne** (permet de corriger une faute du starter via OTA sans release App Store)
- Si ota_packs est vide ou inexistant, le seed script produit exactement le même output qu'avant (pour les 90 starter v1)

## Workflow d'ajout de contenu

1. Append les nouvelles devinettes à `content/ota_packs/<packId>.json` (mêmes règles format v3)
2. Bump `current_version` dans le manifest local (1 → 2 → 3 ...)
3. `dart run tool/seed_content_packs.dart` → produit `build/seed_packs/<packId>/<packId>-vN.json.gz`
4. Upload via `tools/upload_seeds.sh` ou commandes manuelles
5. Met à jour le doc Firestore `content_packs/<packId>` avec le nouveau `hash_sha256`, `size_bytes`, `count`, `current_version`

## Garanties

- Le starter (90 questions) reste **figé** dans l'app — toute installation a au minimum ces 90 questions offline-first
- Les ajouts (ota_packs) ne sont visibles qu'après le 1er sync OTA réussi (cache Drift peuplé)
- Le `CompositeDevinetteRepository` fusionne bundle + cache en mémoire à chaque appel `loadPack`
