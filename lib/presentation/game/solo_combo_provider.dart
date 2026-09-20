import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Série intra-session de victoires consécutives sur les niveaux **Sommets**
/// (mode montagne, hors défi du jour et hors Hub).
///
/// **Non persistée** — volontairement : la série récompense un enchaînement
/// dans une même session de jeu. Elle repart de 0 au lancement de l'app
/// (provider frais), à l'échec (`GamePhase.lost`) et à l'abandon (quitter la
/// partie confirmé, skip gratuit).
///
/// Piloté par `GameController` (incrément / reset sur défaite) et par
/// `GameView` (reset sur abandon). Lu par l'en-tête de jeu (flamme + compteur
/// dès 2) et par le calcul de récompense (cf. `GameEconomyConfig.comboApplies`).
class SoloComboNotifier extends StateNotifier<int> {
  SoloComboNotifier() : super(0);

  /// +1 après une victoire Sommets. Retourne la nouvelle longueur de série
  /// (victoire courante incluse).
  int increment() => state = state + 1;

  /// Remise à zéro (défaite, abandon).
  void reset() => state = 0;
}

/// Un seul compteur pour toute la session (pas `autoDispose` : il doit
/// survivre aux allers-retours entre l'écran de jeu et l'écran Sommets).
final soloComboProvider =
    StateNotifierProvider<SoloComboNotifier, int>((ref) => SoloComboNotifier());
