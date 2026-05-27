import 'dart:async';

import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service de suivi de la série quotidienne (streak).
///
/// Logique :
/// - 1ʳᵉ ouverture jamais enregistrée → série = 1.
/// - Ouverture aujourd'hui (même jour calendaire que la dernière) → no-op.
/// - Ouverture le lendemain de la dernière → série + 1.
/// - Gap > 1 jour → série reset à 1.
///
/// Stocké sous deux clés `SharedPreferences` dédiées, indépendantes
/// du compteur `dailyStreak` de `PlayerProgress` (qui reste affiché
/// dans le profil pour rétrocompat).
class DailyStreakService {
  DailyStreakService(this._prefs);

  static const _kCountKey = 'home_streak_count';
  static const _kLastOpenKey = 'home_streak_last_open';

  final SharedPreferences _prefs;

  /// Met à jour la série en fonction du jour courant et retourne la
  /// nouvelle valeur. Idempotent à l'échelle de la journée.
  Future<int> registerOpen([DateTime? now]) async {
    final today = _dateOnly(now ?? DateTime.now());
    final lastRaw = _prefs.getString(_kLastOpenKey);
    final previous = _prefs.getInt(_kCountKey) ?? 0;

    if (lastRaw == null) {
      await _persist(today, 1);
      return 1;
    }

    final last = DateTime.tryParse(lastRaw);
    if (last == null) {
      await _persist(today, 1);
      return 1;
    }

    final lastDay = _dateOnly(last);
    final delta = today.difference(lastDay).inDays;

    if (delta == 0) return previous;
    if (delta == 1) {
      final next = previous + 1;
      await _persist(today, next);
      return next;
    }
    await _persist(today, 1);
    return 1;
  }

  /// Lecture seule de la série actuelle (sans mise à jour).
  int current() => _prefs.getInt(_kCountKey) ?? 0;

  Future<void> _persist(DateTime day, int value) async {
    await _prefs.setString(_kLastOpenKey, day.toIso8601String());
    await _prefs.setInt(_kCountKey, value);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

final dailyStreakServiceProvider = Provider<DailyStreakService>(
  (ref) => DailyStreakService(ref.watch(sharedPreferencesProvider)),
);

/// Série affichée dans le header du Hub d'Accueil.
///
/// L'appel à `registerOpen()` se fait au `build` du provider (donc à la
/// 1ʳᵉ lecture de la session) : Riverpod garde l'état en cache, donc
/// pas de double-tick pendant la session.
///
/// **Side-effect** : déclenche aussi l'octroi de l'indice gratuit
/// quotidien (`claimFreeHintIfDue`). Greffé ici pour ne pas multiplier
/// les cycles de vie « 1er accès du jour » — toute UI qui watche le
/// streak récupère le freebie au bon moment sans hook dédié.
final dailyStreakProvider = FutureProvider<int>((ref) async {
  final service = ref.watch(dailyStreakServiceProvider);
  final streak = await service.registerOpen();
  // Octroi idempotent de l'indice gratuit du jour. Le notifier
  // garantit le no-op si déjà octroyé aujourd'hui — safe à appeler
  // à chaque rebuild de provider.
  unawaited(
    ref
        .read(playerProgressProvider.notifier)
        .claimFreeHintIfDue(date: DateTime.now()),
  );
  return streak;
});
