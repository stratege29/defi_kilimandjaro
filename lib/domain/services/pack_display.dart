/// Helpers d'affichage des packs côté présentation.
///
/// - [packIdFromDevinetteId] dérive l'id de pack d'un id de devinette. Les
///   devinettes suivent le format `<packId>_<NNN>` (cf. la regex serveur
///   `^[a-z][a-z0-9_]*_\d{3,4}$`, ex. `culture_ci_221`). Cela permet
///   d'afficher la provenance d'une question **en duel** sans aucune
///   modification backend (le client reçoit déjà le `devinette_id`).
/// - [packEmoji] mappe un pack vers un emoji décoratif (pas de champ emoji
///   dans le catalogue pour l'instant ; déplaçable vers `catalog/index` plus
///   tard si besoin).
library;

/// Suffixe numérique terminal d'un id de devinette (`_NNN` ou `_NNNN`).
final RegExp _devinetteSuffix = RegExp(r'_\d{3,4}$');

/// Dérive le `packId` depuis un `devinetteId` au format `<packId>_<NNN>`.
///
/// Retourne `null` si l'id ne suit pas ce format (ex. les samples de fallback
/// serveur `sample_easy_1`) — l'appelant n'affiche alors pas de provenance
/// (dégradation propre).
String? packIdFromDevinetteId(String devinetteId) {
  if (!_devinetteSuffix.hasMatch(devinetteId)) return null;
  final packId = devinetteId.replaceFirst(_devinetteSuffix, '');
  return packId.isEmpty ? null : packId;
}

/// Emoji décoratif associé à un pack. Fallback `🃏` (carte/devinette
/// générique) pour un pack inconnu de la table.
String packEmoji(String packId) => _packEmojis[packId] ?? '🃏';

const Map<String, String> _packEmojis = <String, String>{
  'culture_ci': '🎭',
  'football_ci': '⚽',
  'crack_nouchi': '🗣️',
};
