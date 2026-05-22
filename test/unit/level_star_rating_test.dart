import 'package:defi_kilimandjaro/domain/entities/level_star_rating.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LevelStarRating.computeStars', () {
    test('défaite (won=false) → 0 étoile', () {
      expect(
        LevelStarRating.computeStars(
          won: false,
          hintUsed: false,
          timerSeconds: 30,
          timeLeftAtVictory: 0,
        ),
        0,
      );
    });

    test('victoire lente avec indice → 1 étoile', () {
      // 10s restants sur 30s = 33% → pas de 3e étoile
      // Indice utilisé → pas de 2e étoile
      expect(
        LevelStarRating.computeStars(
          won: true,
          hintUsed: true,
          timerSeconds: 30,
          timeLeftAtVictory: 10,
        ),
        1,
      );
    });

    test('victoire lente sans indice → 2 étoiles', () {
      // 10s restants sur 30s = 33% → pas de 3e étoile
      // Pas d\'indice → 2e étoile acquise
      expect(
        LevelStarRating.computeStars(
          won: true,
          hintUsed: false,
          timerSeconds: 30,
          timeLeftAtVictory: 10,
        ),
        2,
      );
    });

    test('victoire rapide avec indice → 2 étoiles', () {
      // 20s restants sur 30s = 66% → 3e étoile acquise
      // Mais indice utilisé → 2e étoile perdue
      // Donc 1 (win) + 0 (hint) + 1 (vitesse) = 2
      expect(
        LevelStarRating.computeStars(
          won: true,
          hintUsed: true,
          timerSeconds: 30,
          timeLeftAtVictory: 20,
        ),
        2,
      );
    });

    test('victoire rapide sans indice → 3 étoiles', () {
      // 20s restants sur 30s = 66% → 3e étoile
      // Pas d\'indice → 2e étoile
      expect(
        LevelStarRating.computeStars(
          won: true,
          hintUsed: false,
          timerSeconds: 30,
          timeLeftAtVictory: 20,
        ),
        3,
      );
    });

    test('cas limite : exactement 50% du timer → 3e étoile acquise', () {
      // 15s restants sur 30s = 50% pile → seuil inclusif
      expect(
        LevelStarRating.computeStars(
          won: true,
          hintUsed: false,
          timerSeconds: 30,
          timeLeftAtVictory: 15,
        ),
        3,
      );
    });

    test('cas limite : 49% du timer → pas de 3e étoile', () {
      // 14s restants sur 30s = 46% → en-dessous du seuil
      expect(
        LevelStarRating.computeStars(
          won: true,
          hintUsed: false,
          timerSeconds: 30,
          timeLeftAtVictory: 14,
        ),
        2,
      );
    });

    test('seuil 50% scale avec timerSeconds (timer 60s, 30s restants)', () {
      // Sur un timer plus long (palier 4-5), le seuil scale en valeur
      // absolue : 50% de 60s = 30s restants requis.
      expect(
        LevelStarRating.computeStars(
          won: true,
          hintUsed: false,
          timerSeconds: 60,
          timeLeftAtVictory: 30,
        ),
        3,
      );
      expect(
        LevelStarRating.computeStars(
          won: true,
          hintUsed: false,
          timerSeconds: 60,
          timeLeftAtVictory: 29,
        ),
        2,
      );
    });
  });

  group('LevelStarRating.levelKey', () {
    test('format stable mountainId#levelIndex', () {
      expect(
        LevelStarRating.levelKey(mountainId: 'ci_nimba', levelIndex: 3),
        'ci_nimba#3',
      );
    });
  });
}
