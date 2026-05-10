import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:equatable/equatable.dart';

/// Session de jeu active — valeur objet minimal liant une devinette à
/// l'état courant (indices, pièces, temps écoulé).
class GameSession extends Equatable {
  const GameSession({
    required this.devinette,
    required this.startedAt,
    this.hintsUsed = 0,
    this.caurisSpent = 0,
  });

  final Devinette devinette;
  final DateTime startedAt;
  final int hintsUsed;
  final int caurisSpent;

  GameSession copyWith({
    Devinette? devinette,
    DateTime? startedAt,
    int? hintsUsed,
    int? caurisSpent,
  }) {
    return GameSession(
      devinette: devinette ?? this.devinette,
      startedAt: startedAt ?? this.startedAt,
      hintsUsed: hintsUsed ?? this.hintsUsed,
      caurisSpent: caurisSpent ?? this.caurisSpent,
    );
  }

  @override
  List<Object?> get props => [devinette, startedAt, hintsUsed, caurisSpent];
}
