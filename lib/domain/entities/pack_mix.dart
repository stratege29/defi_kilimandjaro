import 'package:equatable/equatable.dart';

/// Pondération de packs pour le tirage des devinettes.
///
/// Invariants (validés à la construction) :
/// - chaque poids > 0 (les poids nuls sont retirés silencieusement par
///   [PackMix.normalized] avant validation — un pack à 0 % n'a pas de
///   place dans le mix) ;
/// - la somme des poids vaut 1.0 (tolérance ±[epsilon]) ;
/// - au moins un pack présent.
///
/// L'appartenance des `packId` à `ownedPacks` est validée **côté provider**
/// (cf. `PackMixNotifier`), pas dans le value object — pour rester pur et
/// testable sans dépendance sur l'état du joueur.
class PackMix extends Equatable {
  /// Constructeur principal. Lève [ArgumentError] si les invariants ne
  /// sont pas respectés. Préfère les factories [PackMix.single] /
  /// [PackMix.uniform] / [PackMix.normalized] dans la majorité des cas.
  PackMix({required Map<String, double> weights})
    : weights = Map<String, double>.unmodifiable(weights) {
    _assertInvariants(this.weights);
  }

  /// Mix mono-pack — équivalent à 100 % sur un seul pack.
  /// Cas du joueur qui n'a pas (encore) acheté de second pack.
  factory PackMix.single(String packId) {
    return PackMix(weights: <String, double>{packId: 1.0});
  }

  /// Distribue équitablement le poids entre les `packIds` (tous en
  /// `1 / N`). Pratique pour initialiser un mix par défaut après l'achat
  /// d'un nouveau pack.
  factory PackMix.uniform(Iterable<String> packIds) {
    final ids = packIds.toSet();
    if (ids.isEmpty) {
      throw ArgumentError.value(packIds, 'packIds', 'must not be empty');
    }
    final share = 1.0 / ids.length;
    return PackMix(
      weights: <String, double>{for (final id in ids) id: share},
    );
  }

  /// Normalise des poids potentiellement non-sommés à 1.0 : retire les
  /// entrées ≤ 0 puis renormalise. Utile pour parser des entrées utilisateur
  /// (ex. sliders qui ne tombent pas pile à 100 %).
  factory PackMix.normalized(Map<String, double> rawWeights) {
    final positive = <String, double>{
      for (final entry in rawWeights.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    if (positive.isEmpty) {
      throw ArgumentError.value(
        rawWeights,
        'rawWeights',
        'must contain at least one positive weight',
      );
    }
    final sum = positive.values.fold<double>(0, (a, b) => a + b);
    return PackMix(
      weights: <String, double>{
        for (final entry in positive.entries) entry.key: entry.value / sum,
      },
    );
  }

  /// Parse une représentation JSON (clé = packId, valeur = poids).
  /// Renvoie `null` si le payload est invalide — l'appelant choisit son
  /// fallback (ex. `PackMix.single(freePackId)`).
  static PackMix? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final parsed = <String, double>{};
    for (final entry in json.entries) {
      final key = entry.key?.toString();
      final value = entry.value;
      if (key == null || key.isEmpty) return null;
      if (value is num) {
        parsed[key] = value.toDouble();
      } else {
        return null;
      }
    }
    if (parsed.isEmpty) return null;
    // Pré-validation : la factory `normalized` lèverait ArgumentError si
    // tous les poids sont ≤ 0, mais le filtrage l'a déjà éliminé en amont.
    // On délègue ici sans try/catch pour respecter `avoid_catching_errors`.
    final positive = <String, double>{
      for (final entry in parsed.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    if (positive.isEmpty) return null;
    return PackMix.normalized(positive);
  }

  /// Pondération `packId → poids ∈ ]0, 1]`. Toujours sommée à 1.0.
  /// Map immuable.
  final Map<String, double> weights;

  /// Tolérance numérique pour la validation de la somme des poids.
  static const double epsilon = 0.001;

  /// Liste des `packId` présents dans le mix.
  Set<String> get packIds => weights.keys.toSet();

  /// True si le mix ne contient qu'un seul pack (poids = 1.0).
  bool get isSingle => weights.length == 1;

  Map<String, dynamic> toJson() => <String, dynamic>{...weights};

  PackMix copyWithWeights(Map<String, double> newWeights) {
    return PackMix.normalized(newWeights);
  }

  static void _assertInvariants(Map<String, double> weights) {
    if (weights.isEmpty) {
      throw ArgumentError.value(
        weights,
        'weights',
        'PackMix must contain at least one entry',
      );
    }
    var sum = 0.0;
    for (final entry in weights.entries) {
      if (entry.value <= 0) {
        throw ArgumentError.value(
          weights,
          'weights',
          'PackMix weight for "${entry.key}" must be > 0 '
              '(got ${entry.value}). Strip zero-weights before constructing.',
        );
      }
      sum += entry.value;
    }
    if ((sum - 1.0).abs() > epsilon) {
      throw ArgumentError.value(
        weights,
        'weights',
        'PackMix weights must sum to 1.0 (±$epsilon), got $sum',
      );
    }
  }

  @override
  List<Object?> get props => [weights];
}
