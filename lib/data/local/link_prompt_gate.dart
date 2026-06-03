import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Moment de jeu d'où provient une invitation à lier le compte.
///
/// Sert uniquement à choisir le titre affiché dans la feuille de liaison
/// (`auth.link_prompt.title_*`). Le cadencement, lui, est global et commun
/// à tous les déclencheurs (cf. [LinkPromptGate]).
enum LinkPromptTrigger {
  /// Un sommet (montagne) vient d'être conquis.
  mountainComplete,

  /// Un duel 1v1 vient de se terminer.
  duelFinished,

  /// Le joueur s'apprête à acheter des cauris / un pack.
  purchase,

  /// Le joueur ouvre l'app avec une série quotidienne en cours.
  streak,
}

/// Cadenceur (« douce ») des invitations à lier un compte anonyme.
///
/// L'app est **anonyme-first** : aucune fonctionnalité n'est verrouillée.
/// On propose seulement, à des moments clés, de lier un compte Google/Apple
/// pour sécuriser la progression. Pour ne pas spammer :
///
/// - **Jamais** plus d'une invite par fenêtre de [_minInterval] (72 h).
/// - **Snooze** de [_snoozeDelay] (7 j) quand l'utilisateur tape « Plus tard ».
/// - **Plafond** total de [_maxShows] affichages sur la durée de vie de l'app.
///
/// La condition « jamais si déjà lié » est gérée par l'appelant (qui ne
/// déclenche la feuille que pour une session anonyme) — ce gate ne stocke
/// donc que l'historique d'affichage.
class LinkPromptGate {
  LinkPromptGate(this._prefs);

  static const _kLastShownKey = 'link_prompt_last_shown_ms';
  static const _kShowCountKey = 'link_prompt_show_count';
  static const _kSnoozeUntilKey = 'link_prompt_snooze_until_ms';

  /// Intervalle minimal entre deux invites (cadence « douce »).
  static const Duration _minInterval = Duration(hours: 72);

  /// Report appliqué quand l'utilisateur choisit « Plus tard ».
  static const Duration _snoozeDelay = Duration(days: 7);

  /// Nombre maximal d'invites sur la durée de vie de l'app.
  static const int _maxShows = 3;

  final SharedPreferences _prefs;

  /// `true` si une invite peut être affichée maintenant compte tenu de la
  /// cadence, du snooze et du plafond. N'inclut PAS le test d'anonymat
  /// (responsabilité de l'appelant).
  bool shouldShow([DateTime? now]) {
    final current = now ?? DateTime.now();

    if ((_prefs.getInt(_kShowCountKey) ?? 0) >= _maxShows) return false;

    final snoozeMs = _prefs.getInt(_kSnoozeUntilKey);
    if (snoozeMs != null &&
        current.isBefore(DateTime.fromMillisecondsSinceEpoch(snoozeMs))) {
      return false;
    }

    final lastMs = _prefs.getInt(_kLastShownKey);
    if (lastMs != null) {
      final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
      if (current.difference(last) < _minInterval) return false;
    }

    return true;
  }

  /// Enregistre qu'une invite vient d'être affichée (incrémente le compteur
  /// et arme la fenêtre de cadence).
  Future<void> recordShown([DateTime? now]) async {
    final current = now ?? DateTime.now();
    await _prefs.setInt(_kLastShownKey, current.millisecondsSinceEpoch);
    await _prefs.setInt(
      _kShowCountKey,
      (_prefs.getInt(_kShowCountKey) ?? 0) + 1,
    );
  }

  /// Reporte la prochaine invite de [_snoozeDelay] (« Plus tard »).
  Future<void> recordSnoozed([DateTime? now]) async {
    final until = (now ?? DateTime.now()).add(_snoozeDelay);
    await _prefs.setInt(_kSnoozeUntilKey, until.millisecondsSinceEpoch);
  }
}

final linkPromptGateProvider = Provider<LinkPromptGate>(
  (ref) => LinkPromptGate(ref.watch(sharedPreferencesProvider)),
);
