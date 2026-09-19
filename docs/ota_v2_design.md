# OTA Content Sync — Design v0.2 / v0.3

## Pourquoi cette doc ?

En v0.1 (mai 2026), le `ManifestSyncService.refresh()` appelé en fire-and-forget dans le post-frame callback du `_BootGate` faisait **planter l'app au boot sur iPhone 16 Pro / iOS 26.4.2** par jetsam OOM kill.

Diagnostic complet après ~15 builds et 8 PRs : le seul code qui causait l'OOM était l'OTA sync. Tout le reste (App Check, AdMob, UMP, AudioEngine preload, FCM, Auth, Crashlytics) fonctionne en parallèle sans dépasser le budget mémoire.

Le fix v0.1 (PR #15) : `unawaited(ref.read(manifestSyncServiceProvider).refresh())` est commenté. L'app boot sur le starter pack bundlé uniquement. Pas de nouveau contenu téléchargé.

Cette doc cadre la ré-activation propre : **v0.2** (service séquentiel + streaming + bouton manuel, livré) puis **v0.3** (déclencheur automatique différé, gaté et scopé, septembre 2026).

## État d'implémentation (2026-09)

| Principe | État | Où |
|---|---|---|
| 1. Pas d'OTA dans la fenêtre de boot | **v0.3** : auto-sync différé + gaté + scopé (voir ci-dessous) | `lib/data/sync/ota_auto_sync.dart`, `_BootGate` dans `lib/main.dart` |
| 2. Un pack à la fois | **fait** (v0.2) : boucle séquentielle + `Future.delayed(Duration.zero)` | `manifest_sync_service.dart` |
| 3. Streaming JSON | **partiel, suffisant** : gzip + sha256 en flux ; un seul `jsonDecode` par pack. Les packs réels font 190–320 Ko décompressés (≈ 1–1,5 Mo transitoires). Garde-fou : cap 5 Mio gzip (`kMaxPackGzipBytes`) + timeout d'inactivité du body | `remote_devinette_pack_datasource.dart` |
| 4. Quota mémoire | **fait** (v0.2) : `didHaveMemoryPressure` → abort ; v0.3 distingue signal frais (report 2 min) et périmé (> 60 s, ignoré) via `lastPressureAt` | `sync_state.dart` |
| 5. Idempotence + checksum | **fait** (v0.2) : skip si `packVersion` + `hashSha256` identiques | `manifest_sync_service.dart` |

### v0.3 — Auto-sync différé, gaté, scopé

Déclencheurs (`OtaAutoSyncScheduler`) :

| Trigger | Scope | Throttle |
|---|---|---|
| Manuel (bouton « Mes packs ») | tous les packs | aucun (inchangé) |
| Différé après `start()` (fin du post-frame du `_BootGate`) | packs possédés, actif en tête | `ota_autosync_min_interval_hours` (6 h), 1re passe jamais throttlée |
| Retour en premier plan (`resumed`) | idem | idem |
| Activation / choix / déblocage d'un pack | ce pack seul | aucun (hash-skip = 1 `whereIn`, 0 download) |

Sas commun à tout déclenchement automatique : `App Check + Auth + Remote Config` prêts → kill-switch `ota_autosync_enabled` → délai `ota_autosync_delay_seconds` (20 s) depuis `start()` → pression mémoire (fraîche : report ; périmée : reset). L'auto-sync n'écrit jamais `manifestSyncStateProvider` (pas de bannière) et invalide `packLiveQuestionCountProvider` + `packUpdatesProvider` quand un pack a changé.

Mutex à scope dans `ManifestSyncService.refresh` : un appel dont le scope est couvert par la sync en vol partage son Future ; sinon il est chaîné après elle (union des scopes). Un tap manuel pendant l'auto-sync reste complet, sans double download.

**Rollback sans release** : console Firebase (projet `kilimandjaro-dev`, celui des builds store) → Remote Config → `ota_autosync_enabled = false` → publier. Effet au prochain boot (fetch RC toutes les heures en release, immédiat en debug). Le refresh manuel reste disponible.

## Cause racine du OOM v0.1

Le `ManifestSyncService.refresh()` actuel (voir `lib/data/sync/manifest_sync_service.dart`) fait grosso modo :

```dart
Future<void> refresh() async {
  final manifests = await remote.fetchAllManifests();          // 1 fetch
  for (final manifest in manifests) {
    final packJson = await remote.downloadPack(manifest);      // download
    final devinettes = jsonDecode(packJson) as List<dynamic>;  // parse en RAM
    await cache.upsertPack(manifest.packId, devinettes);       // write Drift
  }
}
```

Combiné avec :
- AudioEngine `_preloadAll` qui synthétise 16 cues PCM (~50-100 MB peak)
- Firebase / Crashlytics / FCM init natif (~80 MB)
- Drift + Riverpod providers (~50 MB)
- Flutter framework + Skia + assets (~150 MB)

**Total au boot sur iOS 26 : ~400-500 MB peak**. iOS 26 a un budget jetsam plus strict que iOS 17/18 pour les apps en foreground (observé empiriquement). Au-dessus de ~350 MB pendant les 10 premières secondes, kill jetsam.

L'OTA sync chargeait potentiellement plusieurs packs de plusieurs MB chacun **en parallèle / en mémoire simultanément** car `jsonDecode` matérialise tout l'arbre JSON avant d'écrire en base.

## Architecture cible v0.2

### Principe 1 — Pas d'OTA dans la fenêtre de boot

OTA sync ne doit **jamais** télécharger pendant les ~10 premières secondes ni depuis le chemin critique du boot. Un déclencheur automatique est acceptable s'il est **différé** (délai Remote Config depuis la fin du post-frame), **gaté** (kill-switch, pression mémoire, throttle) et **scopé** (packs possédés, un pack à la fois) — c'est la v0.3 décrite plus haut.

**Triggers en place :**

| Trigger | Where | UX |
|---|---|---|
| Manuel par l'utilisateur | « Mes packs » → bouton refresh / bandeau MAJ | Bouton + barre de progression |
| Différé après le boot, puis `resumed` | `OtaAutoSyncScheduler` (`_BootGate` → `start()`) | Silencieux ; compteurs de « Mes packs » invalidés si changement |
| Activation d'un pack | `ref.listen(activePackIdProvider / ownedPacksProvider)` | Silencieux, non bloquant |
| Background fetch iOS (BGTaskScheduler) | non implémenté | — |

### Principe 2 — Un pack à la fois

Itérer sur les manifests séquentiellement, **awaiter chaque download + parse + write avant le suivant**. Pas de `Future.wait` ni de concurrence implicite.

```dart
Future<void> refresh({void Function(double progress)? onProgress}) async {
  final manifests = await remote.fetchAllManifests();
  for (var i = 0; i < manifests.length; i++) {
    await _syncOnePack(manifests[i]);
    onProgress?.call((i + 1) / manifests.length);
    // Yield au scheduler iOS pour qu'il puisse paginer la mémoire.
    await Future<void>.delayed(Duration.zero);
  }
}
```

### Principe 3 — Streaming JSON parsing

`jsonDecode(packJson)` matérialise tout l'arbre en RAM. Pour un pack de 5 MB de JSON, ça peut faire 30-50 MB d'objets Dart.

**Solution** : streamer le JSON ligne par ligne (chaque pack v3 est un `List<Devinette>` → chaque devinette est un objet indépendant) et insérer dans Drift au fil de l'eau.

Soit utiliser `package:jsonl` si format JSONL, soit parser à la main avec `Utf8Decoder` + buffer.

**Plus simple si on contrôle le format côté Firestore/Storage** : héberger chaque devinette comme un document Firestore séparé sous `packs/{packId}/devinettes/{id}`. Puis :

```dart
final snapshot = await firestore
    .collection('packs/$packId/devinettes')
    .get();
for (final doc in snapshot.docs) {  // ← itère sans tout charger
  await cache.upsertDevinette(Devinette.fromJson(doc.data()));
}
```

Firestore retourne déjà en chunks, et chaque doc est petit.

### Principe 4 — Quota mémoire explicite

Avant chaque pack, mesurer la mémoire disponible :

```dart
import 'dart:io';
import 'package:flutter/foundation.dart';

bool _memoryOk() {
  // ProcessInfo.activeMemory > 200 MB → skip et retry plus tard.
  // Sur iOS, on n'a pas d'API directe ; utiliser `dart:io.ProcessInfo`
  // ou un platform channel custom qui appelle `task_info`.
  return true; // TODO
}

for (final manifest in manifests) {
  if (!_memoryOk()) {
    _log.w('Skipping pack ${manifest.packId} : memory pressure');
    break;
  }
  await _syncOnePack(manifest);
}
```

Alternative : enregistrer un `WidgetsBindingObserver.didHaveMemoryPressure()` et avorter le sync en cours.

### Principe 5 — Idempotence + checksum

Chaque pack a un `version` ou `etag` dans son manifest. Si le pack déjà en cache a la même version, **skip** l'opération réseau et le parse.

```dart
Future<void> _syncOnePack(ContentPackManifest manifest) async {
  final cached = await cache.getPackVersion(manifest.packId);
  if (cached == manifest.version) {
    _log.d('Pack ${manifest.packId} v${manifest.version} déjà à jour');
    return;
  }
  // ... download + parse + write ...
}
```

Ça évite de re-télécharger 5 MB pour rien à chaque ouverture de l'écran Settings.

## Architecture proposée v0.2

```
┌─────────────────────────────────────────────────────────┐
│ Settings screen (Mes packs)                             │
│   [Vérifier les mises à jour] ← bouton explicite        │
└──────────────────┬──────────────────────────────────────┘
                   │ tap
                   ▼
┌─────────────────────────────────────────────────────────┐
│ ManifestSyncService.refreshWithProgress(onProgress: ...)│
│   - Fetch manifests (small, 1 req Firestore)            │
│   - Foreach pack (séquentiel) :                         │
│     - Skip si version cache == manifest.version         │
│     - Stream Firestore docs                             │
│     - Upsert un-par-un dans Drift                       │
│     - yield via Future.delayed(Duration.zero)           │
│     - onProgress((i+1) / total)                         │
└─────────────────────────────────────────────────────────┘
```

## Fichiers concernés

- `lib/data/sync/manifest_sync_service.dart` — `refresh({onlyPacks, priorityPack, resetPressureSignal, onProgress})`, mutex à scope, `syncPack`
- `lib/data/sync/ota_auto_sync.dart` — `OtaAutoSyncScheduler`, `deferredBootReadyProvider`, `otaAutoSyncSchedulerProvider`
- `lib/data/datasources/remote_devinette_pack_datasource.dart` — download Storage streamé, cap 5 Mio, timeout d'inactivité
- `lib/presentation/my_packs/my_packs_view.dart` — bouton manuel + progression (inchangé en v0.3)
- `lib/main.dart` — `_BootGate` appelle `otaAutoSyncSchedulerProvider.start()` en fin de post-frame ; `deferredBootReadyProvider` overridé avec `authReady` + `remoteConfigReady`
- `lib/domain/entities/game_economy_config.dart` + `remoteconfig.template.json` — clés `ota_autosync_*`

## Tests

- Unit `manifest_sync_service_test.dart` : séquentialité, idempotence, abort pression, scope, priorité, mutex partagé / chaîné
- Unit `ota_auto_sync_scheduler_test.dart` : kill-switch, délai, throttle, première passe, scope + priorité, pression fraîche / périmée, `resumed`, coalescing, backoff
- Unit `remote_devinette_pack_datasource_test.dart` : gzip/hash, body figé, cap de taille
- Manuel sur simulateur (Xcode, jauge mémoire) : aucun pic dans les 10 premières secondes ; logs `[BOOT] 12 OTA auto-sync scheduled` → `deferred: remote config ready` → `ManifestSync: … (download)` à ~T+20 s

## Annexes — autres learnings v0.1 à conserver

1. **`AppDelegate.swift` `triggerLocalNetworkPermission()`** doit rester sous `#if DEBUG` tant que `NSLocalNetworkUsageDescription` n'est PAS dans Info.plist (sinon crash natif sur iOS 17+). Si tu veux que la perm soit demandée en prod (pour l'emulator Firebase ou autre), il faut re-ajouter la clé dans Info.plist avec un message acceptable par App Review (pas "development only").

2. **`cloud_functions` doit rester à ≥ 6.3.0** pour la compat iOS 26 (la 6.2.0 crash dans `swift_getObjectType` au plugin register).

3. **`AudioEngine._preloadAll()`** est OK seul (~50-100 MB peak) mais cumulé avec OTA sync ça déborde le budget jetsam iOS 26. Si on ajoute d'autres preloads futurs, surveiller la pression mémoire au boot.

4. **App Store Connect builds 1-3** uploadés avec `PRODUCT_NAME=Runner` → process iOS s'appelait "Runner" et les crash reports `.ips` aussi. Depuis build 2 (PR #8), PRODUCT_NAME=Kilimandjaro → process et crash dumps prennent ce nom. CFBundleDisplayName était déjà OK ; ça change juste le nom interne du binaire.

5. **Pour debug release sur device** : `flutter run --release -d <device-id>` plante au moment du `install` ; passer par **Xcode → ouvrir Runner.xcworkspace → sélectionner device + scheme Release → Run** est plus fiable. Logs Dart `print()` ressortent dans la console Xcode (mais PAS dans `sudo log stream` ni Console.app en release).
