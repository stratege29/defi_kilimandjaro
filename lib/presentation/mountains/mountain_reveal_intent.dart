/// Intention de « reveal » d'ascension passée à `MountainListView` via le
/// `extra` de la route `/mountains`.
///
/// Émise par `game_view._advanceAfterVictory` quand une montagne vient d'être
/// conquise : l'écran Sommets se positionne d'abord sur la montagne gravie
/// (`fromId`), marque une pause, puis anime le scroll jusqu'à la nouvelle
/// montagne débloquée (`toId`).
///
/// Fichier dédié (et non défini dans `mountain_list_view.dart`) pour que
/// `game_view` n'importe pas le `_view` Sommets.
class MountainRevealIntent {
  const MountainRevealIntent({required this.fromId, required this.toId});

  /// Id de la montagne tout juste conquise (point de départ du reveal).
  final String fromId;

  /// Id de la nouvelle montagne débloquée (cible du scroll animé).
  final String toId;
}
