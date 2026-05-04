import 'package:equatable/equatable.dart';

/// Une montagne africaine — point culminant d'un pays.
///
/// La progression du jeu se fait du plus petit sommet (Gambie ~53 m)
/// jusqu'au **Kilimandjaro** (5 895 m, Tanzanie), boss final symbolique.
class Mountain extends Equatable {
  const Mountain({
    required this.id,
    required this.name,
    required this.countryCode,
    required this.countryName,
    required this.flagEmoji,
    required this.altitude,
    required this.totalLevels,
    this.completedLevels = 0,
    this.unlocked = false,
  });

  factory Mountain.fromJson(Map<String, dynamic> json) {
    return Mountain(
      id: json['id'] as String,
      name: json['name'] as String,
      countryCode: json['country_code'] as String,
      countryName: json['country_name'] as String,
      flagEmoji: json['flag_emoji'] as String,
      altitude: json['altitude_m'] as int,
      totalLevels: (json['total_levels'] as int?) ?? 6,
      completedLevels: (json['completed_levels'] as int?) ?? 0,
      unlocked: (json['unlocked'] as bool?) ?? false,
    );
  }

  final String id;
  final String name;
  final String countryCode;
  final String countryName;
  final String flagEmoji;

  /// Altitude en mètres.
  final int altitude;

  final int totalLevels;
  final int completedLevels;
  final bool unlocked;

  double get progress =>
      totalLevels == 0 ? 0 : completedLevels / totalLevels;

  Mountain copyWith({
    int? completedLevels,
    bool? unlocked,
  }) {
    return Mountain(
      id: id,
      name: name,
      countryCode: countryCode,
      countryName: countryName,
      flagEmoji: flagEmoji,
      altitude: altitude,
      totalLevels: totalLevels,
      completedLevels: completedLevels ?? this.completedLevels,
      unlocked: unlocked ?? this.unlocked,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        countryCode,
        countryName,
        flagEmoji,
        altitude,
        totalLevels,
        completedLevels,
        unlocked,
      ];
}
