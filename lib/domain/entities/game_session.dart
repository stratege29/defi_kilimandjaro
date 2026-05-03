import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:equatable/equatable.dart';

/// Session de jeu active — valeur objet minimal liant une devinette à
/// l'état courant (indices, pièces, temps écoulé).
class GameSession extends Equatable {
  const GameSession({
    required this.devinette,
    required this.startedAt,
    this.hintsUsed = 0,
    this.coinsSpent = 0,
  });

  final Devinette devinette;
  final DateTime startedAt;
  final int hintsUsed;
  final int coinsSpent;

  GameSession copyWith({
    Devinette? devinette,
    DateTime? startedAt,
    int? hintsUsed,
    int? coinsSpent,
  }) {
    return GameSession(
      devinette: devinette ?? this.devinette,
      startedAt: startedAt ?? this.startedAt,
      hintsUsed: hintsUsed ?? this.hintsUsed,
      coinsSpent: coinsSpent ?? this.coinsSpent,
    );
  }

  @override
  List<Object?> get props => [devinette, startedAt, hintsUsed, coinsSpent];
}
