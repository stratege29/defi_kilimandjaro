import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';
import 'package:equatable/equatable.dart';

/// Snapshot persistant de la progression du joueur.
///
/// Persisté via shared_preferences (Phase 2.3, v1).
/// Évolution v2 : sync Firestore quand authentifié (Phase 4 + multijoueur).
class PlayerProgress extends Equatable {
  PlayerProgress({
    required this.cauris,
    required this.completedLevelsByMountain,
    required this.totalLevelsCompleted,
    required this.dailyStreak,
    required this.ownedPacks,
    PackMix? activePackMix,
    this.lastPlayDate,
    this.consecutiveFailures = 0,
    this.noAdsPurchased = false,
    this.recentDevinetteIds = const <String>[],
    this.freePackChosen,
  }) : activePackMix =
           activePackMix ?? _defaultPackMix(ownedPacks, freePackChosen);

  /// État initial pour un nouveau joueur.
  ///
  /// Aucun pack possédé tant que l'onboarding n'a pas tranché : c'est le
  /// flow "choisir mon pack gratuit" qui appelle [PlayerProgressNotifier
  /// .chooseFreePack] et initialise `ownedPacks + freePackChosen` de
  /// façon atomique.
  factory PlayerProgress.initial() => PlayerProgress(
    cauris: 120,
    completedLevelsByMountain: const <String, int>{},
    totalLevelsCompleted: 0,
    dailyStreak: 0,
    ownedPacks: const <String>{},
    activePackMix: _placeholderMix,
  );

  factory PlayerProgress.fromJson(Map<String, dynamic> json) {
    final ownedPacks =
        ((json['owned_packs'] as List<dynamic>?) ?? const <dynamic>[])
            .map((e) => e.toString())
            .toSet();
    final freePack = json['free_pack_chosen'] as String?;
    final parsedMix = PackMix.tryFromJson(json['pack_mix']);
    return PlayerProgress(
      // Tolère l'ancienne clé `coins` pour ne pas perdre le solde des
      // joueurs existants après le rebranding Cauris.
      cauris: (json['cauris'] as int?) ?? (json['coins'] as int?) ?? 120,
      completedLevelsByMountain:
          ((json['levels'] as Map<String, dynamic>?) ?? <String, dynamic>{})
              .map((k, v) => MapEntry(k, v as int)),
      totalLevelsCompleted: (json['total'] as int?) ?? 0,
      dailyStreak: (json['streak'] as int?) ?? 0,
      lastPlayDate: json['last_play'] == null
          ? null
          : DateTime.tryParse(json['last_play'] as String),
      consecutiveFailures: (json['consecutive_failures'] as int?) ?? 0,
      noAdsPurchased: (json['no_ads'] as bool?) ?? false,
      recentDevinetteIds:
          ((json['recent_devinettes'] as List<dynamic>?) ?? <dynamic>[])
              .map((e) => e as String)
              .toList(growable: false),
      ownedPacks: ownedPacks,
      freePackChosen: freePack,
      activePackMix:
          parsedMix ?? _defaultPackMix(ownedPacks, freePack),
    );
  }

  /// Mix utilisé tant que l'onboarding n'a pas tranché — pointe sur un
  /// pack-token sentinelle (`_pending_`) pour signaler "non choisi". Le
  /// tirage doit refuser ce mix : l'app ne doit pas démarrer une partie
  /// avant que l'utilisateur ait choisi son pack gratuit.
  ///
  /// Toujours préférer le getter [activePackMix] de l'instance courante
  /// + le drapeau [hasChosenFreePack] dans la couche présentation.
  static final PackMix _placeholderMix = PackMix.single(packPendingSentinel);

  /// Sentinelle utilisée par le mix par défaut avant choix du pack gratuit.
  /// Ne doit jamais être passée à un repository de devinettes.
  static const String packPendingSentinel = '_pending_';

  /// Construit un mix par défaut cohérent à partir de l'état persisté.
  /// Précédence : `freePackChosen` > 1er `ownedPacks` > sentinelle.
  static PackMix _defaultPackMix(
    Set<String> ownedPacks,
    String? freePackChosen,
  ) {
    if (freePackChosen != null && freePackChosen.isNotEmpty) {
      return PackMix.single(freePackChosen);
    }
    if (ownedPacks.isNotEmpty) {
      return PackMix.single(ownedPacks.first);
    }
    return _placeholderMix;
  }

  /// Solde de Cauris de Sagesse (cauris = monnaie shell d'Afrique de l'Ouest).
  final int cauris;

  /// Niveaux complétés par montagne (mountainId → count).
  final Map<String, int> completedLevelsByMountain;

  /// Total cumul de niveaux gagnés (utile pour titres honorifiques).
  final int totalLevelsCompleted;

  /// Streak quotidienne.
  final int dailyStreak;

  /// Dernière date de jeu (jour calendaire, sans heure).
  final DateTime? lastPlayDate;

  /// Compteur d'échecs consécutifs (reset à chaque victoire).
  /// Sert de trigger pour l'interstitielle (cf. plan.md §4 — 1 sur 3 échecs).
  final int consecutiveFailures;

  /// Achat non-consumable "Supprimer les pubs" (4,99 €).
  final bool noAdsPurchased;

  /// Ids des dernières devinettes jouées (les plus récentes en tête).
  /// Limité à 5 entrées dans le notifier. Utilisé pour exclure ces ids
  /// du tirage `randomFromWorldExcluding` → évite la frustration de
  /// retomber sur la même devinette deux fois de suite.
  final List<String> recentDevinetteIds;

  /// Packs thématiques possédés par le joueur (inclut systématiquement
  /// le pack gratuit choisi à l'onboarding).
  ///
  /// Set immuable par contrat — mutations via `copyWith` + persistance.
  final Set<String> ownedPacks;

  /// Pack gratuit choisi au 1er lancement. **Immuable une fois défini**
  /// (règle produit verrouillée par le PO). `null` tant que l'onboarding
  /// n'a pas tranché.
  final String? freePackChosen;

  /// Pondération active pour le tirage des devinettes.
  /// Default = `PackMix.single(freePackChosen)` quand un pack est choisi,
  /// sinon mix sentinelle (`_pending_`).
  final PackMix activePackMix;

  /// True quand l'utilisateur a déjà choisi son pack gratuit (gating
  /// d'onboarding).
  bool get hasChosenFreePack => freePackChosen != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'cauris': cauris,
    'levels': completedLevelsByMountain,
    'total': totalLevelsCompleted,
    'streak': dailyStreak,
    'last_play': lastPlayDate?.toIso8601String(),
    'consecutive_failures': consecutiveFailures,
    'no_ads': noAdsPurchased,
    'recent_devinettes': recentDevinetteIds,
    'owned_packs': ownedPacks.toList(growable: false),
    if (freePackChosen != null) 'free_pack_chosen': freePackChosen,
    'pack_mix': activePackMix.toJson(),
  };

  /// Combien de niveaux complétés sur cette montagne.
  int levelsOn(String mountainId) => completedLevelsByMountain[mountainId] ?? 0;

  PlayerProgress copyWith({
    int? cauris,
    Map<String, int>? completedLevelsByMountain,
    int? totalLevelsCompleted,
    int? dailyStreak,
    DateTime? lastPlayDate,
    int? consecutiveFailures,
    bool? noAdsPurchased,
    List<String>? recentDevinetteIds,
    Set<String>? ownedPacks,
    String? freePackChosen,
    PackMix? activePackMix,
  }) {
    return PlayerProgress(
      cauris: cauris ?? this.cauris,
      completedLevelsByMountain:
          completedLevelsByMountain ?? this.completedLevelsByMountain,
      totalLevelsCompleted: totalLevelsCompleted ?? this.totalLevelsCompleted,
      dailyStreak: dailyStreak ?? this.dailyStreak,
      lastPlayDate: lastPlayDate ?? this.lastPlayDate,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      noAdsPurchased: noAdsPurchased ?? this.noAdsPurchased,
      recentDevinetteIds: recentDevinetteIds ?? this.recentDevinetteIds,
      ownedPacks: ownedPacks ?? this.ownedPacks,
      freePackChosen: freePackChosen ?? this.freePackChosen,
      activePackMix: activePackMix ?? this.activePackMix,
    );
  }

  @override
  List<Object?> get props => [
    cauris,
    completedLevelsByMountain,
    totalLevelsCompleted,
    dailyStreak,
    lastPlayDate,
    consecutiveFailures,
    noAdsPurchased,
    recentDevinetteIds,
    ownedPacks,
    freePackChosen,
    activePackMix,
  ];
}
