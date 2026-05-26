import 'package:defi_kilimandjaro/data/firebase/remote_config_service.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Compteur quotidien de rewarded videos visionnées par device.
///
/// Anti-farming + préservation de la conversion IAP : au-delà du cap
/// (`GameEconomyConfig.rewardedDailyCap`, défaut 5/jour) on bloque l'offre
/// dans toute l'UI (chip in-game, victory double, shop bonus). Reset
/// implicite au changement de date locale — la date est rangée à côté du
/// compteur et un mismatch déclenche un reset transparent à la prochaine
/// lecture.
///
/// Stockage `shared_preferences` (local-only, pas de cross-device — c'est
/// volontaire pour limiter la surface d'abus sans login Firestore).
///
/// **Pattern Riverpod** : exposé via [StateNotifier] pour que l'UI se
/// re-render automatiquement après chaque [recordView] (un compteur lu
/// directement depuis SharedPreferences ne déclencherait pas
/// l'invalidation, et les chips/CTA resteraient affichés à tort).
class RewardedDailyCapService extends StateNotifier<int> {
  RewardedDailyCapService(this._prefs) : super(_initialCount(_prefs));

  static const String _kCountKey = 'rewarded_daily_count';
  static const String _kDateKey = 'rewarded_daily_date';

  final SharedPreferences _prefs;

  /// Compteur du jour courant. Hot-read : recalcule si la date change
  /// pendant la session (rare, mais correct lors d'un passage de minuit).
  int get countToday {
    final stored = _prefs.getString(_kDateKey);
    final today = _todayKey();
    if (stored != today) {
      // Détecte le passage de minuit : reset transparent puis sync l'état.
      if (state != 0) state = 0;
      return 0;
    }
    final persisted = _prefs.getInt(_kCountKey) ?? 0;
    if (persisted != state) state = persisted;
    return persisted;
  }

  /// Vrai si l'utilisateur peut encore voir une rewarded aujourd'hui.
  bool canShow(int dailyCap) => countToday < dailyCap;

  /// À appeler après une rewarded **terminée avec récompense** (pas après
  /// un dismiss avant la fin). Persiste le compteur + la date et notifie
  /// les watchers.
  Future<void> recordView() async {
    final today = _todayKey();
    final stored = _prefs.getString(_kDateKey);
    final current = stored == today ? (_prefs.getInt(_kCountKey) ?? 0) : 0;
    final next = current + 1;
    await _prefs.setString(_kDateKey, today);
    await _prefs.setInt(_kCountKey, next);
    state = next;
  }

  /// Lecture initiale au boot — applique le reset implicite si la date
  /// stockée n'est plus aujourd'hui.
  static int _initialCount(SharedPreferences prefs) {
    final stored = prefs.getString(_kDateKey);
    final today = _todayKey();
    if (stored != today) return 0;
    return prefs.getInt(_kCountKey) ?? 0;
  }

  /// Format YYYY-MM-DD en time-zone locale. Pas d'UTC : on veut que le
  /// reset soit aligné avec la perception "minuit chez moi" du joueur.
  static String _todayKey() {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }
}

final rewardedDailyCapServiceProvider =
    StateNotifierProvider<RewardedDailyCapService, int>((ref) {
  return RewardedDailyCapService(ref.watch(sharedPreferencesProvider));
});

/// Helper unifié réactif : true si l'UI doit afficher une offre rewarded.
/// Combine killswitch Remote Config + cap quotidien atteint. Re-évalué
/// automatiquement après chaque `recordView()` ou changement de RC.
final canOfferRewardedProvider = Provider<bool>((ref) {
  final econ = ref.watch(gameEconomyConfigProvider);
  if (econ.adsKillswitch) return false;
  final count = ref.watch(rewardedDailyCapServiceProvider);
  return count < econ.rewardedDailyCap;
});
