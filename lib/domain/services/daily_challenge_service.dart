import 'package:defi_kilimandjaro/domain/entities/player_progress.dart';

/// Défi du jour — sélection déterministe et helpers d'état.
///
/// **Modèle MVP** (validé avec le PO, mai 2026) :
/// - 1 énigme par jour calendaire local
/// - Difficulté fixe Tier 3 (mots de 7 lettres, ~42s, 1 distracteur)
/// - Récompense fixe : 100 cauris en cas de victoire
/// - 1 essai par jour. Échec ou skip d'un jour ⇒ streak reset à 0
/// - Pool source : pack actif du joueur (cf. `activePackMix`)
///
/// La sélection est **déterministe** : pour une date donnée et un pool
/// candidat trié, le même devinetteId sera toujours retourné. Cela
/// garantit que tous les joueurs partageant le même pack actif
/// (ex. `culture_ci`) voient le même mot du jour — élément de
/// conversation et de partage social.
///
/// Fonction pure, sans dépendance Flutter — testable trivialement.
abstract final class DailyChallengeService {
  /// Récompense en cauris octroyée en cas de victoire du daily.
  /// Constante locale (à promouvoir vers Remote Config si A/B testé).
  static const int rewardCauris = 100;

  /// Paliers de bonus série (en jours de streak consécutifs) et leur
  /// récompense en cauris. Octroyée **une seule fois**, à la victoire
  /// qui fait basculer le streak sur le palier exact.
  ///
  /// Calibrage économique :
  /// - **3 jours / +50 🐚** : jalon de validation (le joueur teste le
  ///   loop, on récompense le premier engagement réel).
  /// - **7 jours / +200 🐚** : jalon hebdomadaire (le rituel s'ancre).
  /// - **30 jours / +1000 🐚** : jalon mensuel — équivaut à 10 reveals
  ///   T3+ ou ~5 sessions de pure récompense daily (marketing).
  static const Map<int, int> _streakBonusByMilestone = <int, int>{
    3: 50,
    7: 200,
    30: 1000,
  };

  /// Retourne le bonus en cauris à octroyer quand le streak passe à
  /// `newStreak`. Zéro si ce jour ne correspond pas à un palier exact.
  ///
  /// **Une seule fois par palier** : un joueur à streak=31 ne touche pas
  /// le bonus 30 (déjà reçu à streak=30). Idem pour 4/8/... — pas de
  /// rétroactivité.
  static int bonusForStreak(int newStreak) {
    return _streakBonusByMilestone[newStreak] ?? 0;
  }

  /// Liste ordonnée des paliers de streak (3, 7, 30) — exposé pour l'UI
  /// qui pourrait afficher la prochaine cible.
  static List<int> get streakMilestones =>
      _streakBonusByMilestone.keys.toList(growable: false)..sort();

  /// Coût en cauris pour acheter un **freeze token** (protection
  /// anti-day-skip). Sweet spot 1:1 avec la récompense daily moyenne
  /// (~142 🐚 sur 30 jours bonus inclus) — l'achat reste accessible mais
  /// crée un vrai sink. À promouvoir Remote Config pour A/B tester.
  static const int freezeTokenCost = 150;

  /// Plafond de freeze tokens en stock pour éviter le farming abusif.
  /// 3 = couvre une absence d'une demi-semaine sans rendre le streak
  /// trivial.
  static const int maxFreezeTokens = 3;

  /// Pioche l'id de devinette du défi du jour parmi `candidates` pour la
  /// date `date`. Retourne `null` si `candidates` est vide.
  ///
  /// **Algorithme** :
  /// 1. Trie défensivement `candidates` (ordre stable, indépendant de
  ///    l'ordre source pour rester invariant cross-platform).
  /// 2. Hash FNV-1a 32-bit de la clé `yyyy-MM-dd` ⇒ index dans le pool.
  /// 3. `candidates[index % candidates.length]`.
  ///
  /// Pourquoi pas Object.hashCode : il varie d'un build à l'autre.
  /// Pourquoi pas Random(seed) : Dart `Random` n'est pas portable cross-
  /// platform (impl différente Dart VM vs Web). FNV-1a est bit-identique
  /// partout et la qualité est largement suffisante pour distribuer
  /// 365 jours sur N candidats.
  static String? pickDevinetteIdForDate({
    required DateTime date,
    required List<String> candidates,
  }) {
    if (candidates.isEmpty) return null;
    final sorted = List<String>.of(candidates)..sort();
    final hash = _fnv1a32(dailyKeyForDate(date));
    return sorted[hash % sorted.length];
  }

  /// Clé canonique pour une date donnée. Format `yyyy-MM-dd` en local —
  /// **pas UTC** : un joueur à Abidjan doit voir un défi changer à minuit
  /// local, pas à minuit UTC.
  static String dailyKeyForDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// True si le joueur a déjà tenté le défi du jour `date`.
  /// Utilise `_isSameDay` pour comparer (ignore l'heure stockée).
  static bool isPlayedOn({
    required PlayerProgress progress,
    required DateTime date,
  }) {
    final last = progress.lastDailyChallengeDate;
    if (last == null) return false;
    return _isSameDay(last, date);
  }

  /// True si le streak doit être considéré comme **cassé** au jour
  /// `today` — c'est-à-dire si plus d'un jour calendaire s'est écoulé
  /// depuis le dernier daily joué. Utilisé par l'UI pour afficher
  /// « streak perdu » avant que le joueur ne joue le défi du jour.
  ///
  /// Retourne `false` si :
  /// - jamais joué de daily (`lastDailyChallengeDate == null`),
  /// - dernier daily joué aujourd'hui ou hier.
  ///
  /// Retourne `true` si gap ≥ 2 jours (skip).
  static bool isStreakBroken({
    required PlayerProgress progress,
    required DateTime today,
  }) {
    final last = progress.lastDailyChallengeDate;
    if (last == null) return false;
    final lastDay = _dayOnly(last);
    final todayDay = _dayOnly(today);
    return todayDay.difference(lastDay).inDays >= 2;
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static int _fnv1a32(String input) {
    const fnvOffset = 0x811c9dc5;
    const fnvPrime = 0x01000193;
    var hash = fnvOffset;
    for (final code in input.codeUnits) {
      hash ^= code;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash;
  }
}
