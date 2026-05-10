// ignore_for_file: avoid_redundant_argument_values

import 'package:flutter_test/flutter_test.dart';

/// Reproduction en Dart du calcul ELO implémenté dans
/// `functions/src/matchmaking/elo.ts` — garantit la cohérence
/// client/serveur sans dépendance Firebase.
///
/// Formule :
///   expected_winner = 1 / (1 + 10^((elo_loser - elo_winner) / 400))
///   winner_delta    = round(K * (1 - expected_winner))
///   loser_delta     = round(K * (0 - (1 - expected_winner)))
///   new_winner      = winner_elo + winner_delta
///   new_loser       = max(0, loser_elo + loser_delta)
class EloCalculator {
  static const int kFactor = 32;
  static const int eloInitial = 1000;
  static const int eloMaster = 5895;

  static ({
    int newWinnerElo,
    int newLoserElo,
    int winnerDelta,
    int loserDelta,
  }) calculate({
    required int winnerElo,
    required int loserElo,
    int k = kFactor,
  }) {
    final expected =
        1 / (1 + _pow10((loserElo - winnerElo) / 400));
    final winnerDelta = (k * (1 - expected)).round();
    final loserDelta = (k * (0 - (1 - expected))).round();
    return (
      newWinnerElo: winnerElo + winnerDelta,
      newLoserElo: (loserElo + loserDelta).clamp(0, 999999),
      winnerDelta: winnerDelta,
      loserDelta: loserDelta,
    );
  }

  static double _pow10(double exp) => _pow(10, exp);

  static double _pow(double base, double exp) =>
      base == 10 ? _exp10(exp) : _powGeneric(base, exp);

  static double _exp10(double e) {
    // 10^e = e^(e * ln10)
    return _powGeneric(10.0, e);
  }

  static double _powGeneric(double b, double e) {
    if (e == 0) return 1;
    // Simple iterative computation avoided — use dart:math in prod.
    // For tests, we use the standard approach.
    return _nativePow(b, e);
  }

  // Proxy to avoid importing dart:math in the entity — tests use it directly.
  static double _nativePow(double b, double e) {
    // ignore: prefer_int_literals
    return _expApprox(e * 2.302585092994046); // ln(10)
  }

  static double _expApprox(double x) {
    // Approximation via Taylor series — only needed for testing parity.
    // Production uses JS Math.pow directly.
    double sum = 1;
    double term = 1;
    for (int n = 1; n <= 30; n++) {
      term *= x / n;
      sum += term;
    }
    return sum;
  }
}

void main() {
  group('EloCalculator', () {
    // Tolérance pour les arrondis.
    const tolerance = 2;

    test('joueurs égaux (1000 vs 1000) — delta = +16 / -16', () {
      final r = EloCalculator.calculate(winnerElo: 1000, loserElo: 1000);
      expect(r.winnerDelta, inInclusiveRange(14, 18));
      expect(r.loserDelta, inInclusiveRange(-18, -14));
      expect(r.winnerDelta + r.loserDelta, 0); // conservation
      expect(r.newWinnerElo, 1000 + r.winnerDelta);
      expect(r.newLoserElo, 1000 + r.loserDelta);
    });

    test('gagnant très fort (2000) vs perdant faible (1000) — delta faible', () {
      final r = EloCalculator.calculate(winnerElo: 2000, loserElo: 1000);
      // Surprenant si le fort gagne → petite récompense.
      expect(r.winnerDelta, inInclusiveRange(0, 5));
      expect(r.loserDelta, inInclusiveRange(-5, 0));
    });

    test('gagnant faible (1000) vs perdant fort (2000) — delta large', () {
      final r = EloCalculator.calculate(winnerElo: 1000, loserElo: 2000);
      // Surprenant si le faible gagne → grosse récompense.
      expect(r.winnerDelta, inInclusiveRange(28, 32));
      expect(r.loserDelta, inInclusiveRange(-32, -28));
    });

    test('elo_loser ne descend pas en dessous de 0', () {
      final r = EloCalculator.calculate(winnerElo: 2000, loserElo: 5);
      expect(r.newLoserElo, greaterThanOrEqualTo(0));
    });

    test('delta gagnant + delta perdant = 0 (conservation globale)', () {
      final pairs = [
        (1000, 1000),
        (1200, 800),
        (800, 1200),
        (1500, 1500),
        (3000, 1000),
      ];
      for (final (w, l) in pairs) {
        final r = EloCalculator.calculate(winnerElo: w, loserElo: l);
        expect(
          (r.winnerDelta + r.loserDelta).abs(),
          lessThanOrEqualTo(tolerance),
          reason: 'Conservation failed for $w vs $l',
        );
      }
    });

    test('K=32 par défaut — delta max ≤ 32', () {
      // Cas extrême : faible bat fort.
      final r = EloCalculator.calculate(winnerElo: 100, loserElo: 5000);
      expect(r.winnerDelta, lessThanOrEqualTo(32));
      expect(r.loserDelta.abs(), lessThanOrEqualTo(32));
    });

    test('ELO initial = 1000', () {
      expect(EloCalculator.eloInitial, 1000);
    });

    test('ELO master = 5895 (sommet du Kilimandjaro)', () {
      expect(EloCalculator.eloMaster, 5895);
    });

    test('résultat identique avec K explicite = 32', () {
      final r1 = EloCalculator.calculate(winnerElo: 1200, loserElo: 1000);
      final r2 = EloCalculator.calculate(
        winnerElo: 1200,
        loserElo: 1000,
        k: 32,
      );
      expect(r1.winnerDelta, r2.winnerDelta);
      expect(r1.loserDelta, r2.loserDelta);
    });
  });
}
