import 'package:equatable/equatable.dart';

/// Source d'une devinette dans le pipeline de contenu.
///
/// - [bundled] : starter pack embarqué dans l'APK (`assets/data/devinettes/starter/`).
/// - [remotePack] : pack officiel téléchargé depuis Cloud Storage (manifest Firestore).
/// - [community] : devinette utilisateur approuvée, livrée via le pack communautaire
///   reconstruit côté serveur (mêmes mécaniques que [remotePack]).
enum DevinetteSource { bundled, remotePack, community }

/// Langue par défaut pour le fallback des champs multilingues.
const String kDevinetteDefaultLang = 'fr';

/// Langue active à utiliser quand on lit les getters localisés (`riddle`,
/// `explanation`, `proverb`). Mise à jour au boot de l'app depuis
/// `context.locale.languageCode` (easy_localization).
///
/// Wrapper mutable plutôt que paramètre passé partout : les call-sites existants
/// continuent d'appeler `devinette.riddle` sans modification.
abstract final class DevinetteLocale {
  /// Langue actuellement utilisée pour la résolution des champs localisés.
  /// À assigner au boot de l'app et à chaque changement de langue.
  static String activeLang = kDevinetteDefaultLang;
}

/// Une devinette culturelle ivoirienne (cf. devinette-curator.md pour le format JSON).
///
/// Schema **format_version 2** (multilingue) :
/// - `riddle`/`explanation`/`proverb` sont stockés en `Map<String, String>`
///   indexé par code langue ISO (`fr`, `en`, ...).
/// - `answer` reste mono-langue (mot canonique majuscules sans accent).
///
/// Compatibilité v1 (legacy) : `Devinette.fromJson` accepte aussi les anciens
/// fichiers où `riddle`/`explanation`/`proverb` sont des `String` plats — ils
/// sont automatiquement enrobés sous la clé `'fr'`.
class Devinette extends Equatable {
  const Devinette({
    required this.id,
    required this.world,
    required this.country,
    required this.answer,
    required this.lettersPool,
    required this.riddleByLang,
    required this.explanationByLang,
    required this.proverbByLang,
    required this.difficulty,
    required this.estimatedTimeS,
    required this.tags,
    this.answerNormalized,
    this.imageSvg,
    this.imageUrl,
    this.formatVersion = 2,
    this.source = DevinetteSource.bundled,
  });

  /// Parse un Map JSON en Devinette. Accepte v1 (riddle/explanation/proverb en
  /// `String`) et v2 (en `Map<String, String>`).
  factory Devinette.fromJson(
    Map<String, dynamic> json, {
    DevinetteSource source = DevinetteSource.bundled,
  }) {
    final formatVersion = (json['format_version'] as int?) ?? 1;
    return Devinette(
      id: json['id'] as String,
      world: json['world'] as String,
      country: json['country'] as String,
      answer: (json['answer'] as String).toUpperCase(),
      answerNormalized: json['answer_normalized'] as String?,
      lettersPool: List<String>.from(
        (json['letters_pool'] as List<dynamic>).map((e) => e.toString()),
      ),
      riddleByLang: _parseLocalizedField(json['riddle']),
      explanationByLang: _parseLocalizedField(json['explanation']),
      proverbByLang: _parseLocalizedField(json['proverb']),
      imageSvg: json['image_svg'] as String?,
      imageUrl: json['image_url'] as String?,
      difficulty: json['difficulty'] as int,
      estimatedTimeS: json['estimated_time_s'] as int,
      tags: List<String>.from(
        (json['tags'] as List<dynamic>).map((e) => e.toString()),
      ),
      formatVersion: formatVersion,
      source: _sourceFromString(json['source'] as String?) ?? source,
    );
  }

  /// Sérialise en JSON v2 (multilingue). Utilisé par le cache local Drift et
  /// les outils de migration.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'world': world,
      'country': country,
      'answer': answer,
      if (answerNormalized != null) 'answer_normalized': answerNormalized,
      'letters_pool': lettersPool,
      'riddle': riddleByLang,
      'explanation': explanationByLang,
      'proverb': proverbByLang,
      if (imageSvg != null) 'image_svg': imageSvg,
      if (imageUrl != null) 'image_url': imageUrl,
      'difficulty': difficulty,
      'estimated_time_s': estimatedTimeS,
      'tags': tags,
      'format_version': formatVersion,
      'source': source.name,
    };
  }

  static Map<String, String> _parseLocalizedField(dynamic raw) {
    if (raw == null) return const <String, String>{};
    if (raw is String) {
      // v1 fallback : on enrobe sous la langue par défaut.
      return <String, String>{kDevinetteDefaultLang: raw};
    }
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }
    return const <String, String>{};
  }

  static DevinetteSource? _sourceFromString(String? raw) {
    if (raw == null) return null;
    for (final v in DevinetteSource.values) {
      if (v.name == raw) return v;
    }
    return null;
  }

  final String id;
  final String world;
  final String country;

  /// Mot réponse en majuscules sans accent (ex. 'FOUTOU', 'ATTIEKE').
  /// Convention projet : pas d'accents pour matcher les `lettersPool`.
  final String answer;

  /// Forme ASCII-normalisée pour la recherche/dédup (ex. 'foutou', 'attieke').
  /// Optionnel — calculé à la volée si absent.
  final String? answerNormalized;

  /// Lettres à disposer dans la grille — reflète exactement les lettres du mot,
  /// avec doublons (ex. FOUTOU = 2xO, 2xU).
  final List<String> lettersPool;

  /// Devinette texte par code langue ISO (`fr`, `en`, ...).
  final Map<String, String> riddleByLang;
  final Map<String, String> explanationByLang;
  final Map<String, String> proverbByLang;

  final String? imageSvg;
  final String? imageUrl;
  final int difficulty;
  final int estimatedTimeS;
  final List<String> tags;

  /// Version du schema de cette devinette. v2 = multilingue.
  final int formatVersion;

  /// Origine du contenu (bundle / pack distant / communautaire).
  final DevinetteSource source;

  /// Devinette dans la langue active (`DevinetteLocale.activeLang`).
  /// Fallback sur `fr`, puis sur la première valeur disponible.
  String get riddle => localized(riddleByLang);

  /// Explication dans la langue active.
  String get explanation => localized(explanationByLang);

  /// Proverbe dans la langue active.
  String get proverb => localized(proverbByLang);

  /// Récupère un champ localisé avec fallback `lang` → `fr` → première valeur.
  String localized(Map<String, String> field, {String? lang}) {
    final target = lang ?? DevinetteLocale.activeLang;
    final value = field[target];
    if (value != null && value.isNotEmpty) return value;
    final fallback = field[kDevinetteDefaultLang];
    if (fallback != null && fallback.isNotEmpty) return fallback;
    if (field.isNotEmpty) return field.values.first;
    return '';
  }

  /// Liste des langues disponibles pour cette devinette.
  Set<String> get availableLangs {
    return <String>{
      ...riddleByLang.keys,
      ...explanationByLang.keys,
      ...proverbByLang.keys,
    };
  }

  Devinette copyWith({
    String? id,
    String? world,
    String? country,
    String? answer,
    String? answerNormalized,
    List<String>? lettersPool,
    Map<String, String>? riddleByLang,
    Map<String, String>? explanationByLang,
    Map<String, String>? proverbByLang,
    String? imageSvg,
    String? imageUrl,
    int? difficulty,
    int? estimatedTimeS,
    List<String>? tags,
    int? formatVersion,
    DevinetteSource? source,
  }) {
    return Devinette(
      id: id ?? this.id,
      world: world ?? this.world,
      country: country ?? this.country,
      answer: answer ?? this.answer,
      answerNormalized: answerNormalized ?? this.answerNormalized,
      lettersPool: lettersPool ?? this.lettersPool,
      riddleByLang: riddleByLang ?? this.riddleByLang,
      explanationByLang: explanationByLang ?? this.explanationByLang,
      proverbByLang: proverbByLang ?? this.proverbByLang,
      imageSvg: imageSvg ?? this.imageSvg,
      imageUrl: imageUrl ?? this.imageUrl,
      difficulty: difficulty ?? this.difficulty,
      estimatedTimeS: estimatedTimeS ?? this.estimatedTimeS,
      tags: tags ?? this.tags,
      formatVersion: formatVersion ?? this.formatVersion,
      source: source ?? this.source,
    );
  }

  @override
  List<Object?> get props => [
        id,
        world,
        country,
        answer,
        answerNormalized,
        lettersPool,
        riddleByLang,
        explanationByLang,
        proverbByLang,
        imageSvg,
        imageUrl,
        difficulty,
        estimatedTimeS,
        tags,
        formatVersion,
        source,
      ];
}
