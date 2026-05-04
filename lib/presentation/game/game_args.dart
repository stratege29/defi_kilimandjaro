import 'package:defi_kilimandjaro/domain/entities/devinette.dart';

/// Argument de navigation pour `/game`.
///
/// `mountainId` est null quand le jeu est lancé depuis le Hub des mondes
/// thématiques (sans contexte géographique).
class GameArgs {
  const GameArgs({
    required this.devinette,
    this.mountainId,
  });

  final Devinette devinette;
  final String? mountainId;
}
