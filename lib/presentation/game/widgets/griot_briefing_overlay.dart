import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Overlay de mise en garde d'ascension (« la pente se raidit » /
/// « gardien du sommet ») affiché juste avant que le timer démarre sur les
/// niveaux qui contiennent des modifiers ou un boss.
///
/// Style aligné sur les autres popups « Vert Nuit » (cf. `DailyStreakDialog`)
/// : `surfaceContainer`, eyebrow doré all-caps, `AppButton` pleine largeur.
///
/// Best practices (cf. discussion produit) :
/// - **Pause forcée** du timer pendant la lecture (côté `_GameViewState`)
/// - **Friction minimale** : un seul tap sur le CTA suffit, et le tap hors
///   de la card ferme également l'overlay (barrierDismissible)
/// - **Cadre escalade** : le titre parle du sommet/de la pente, pas d'un
///   « Niveau Spécial! », pour rester dans la métaphore de l'ascension
/// - **Ne pas réafficher au restart** : un flag `_briefingShown` côté view
///   garantit que la réessai après échec ne re-déclenche pas le briefing
///
/// Tous les modifiers décrits ici doivent avoir une clé i18n
/// `game.briefing.modifier.<nom>` (name + desc) dans `fr.json`/`en.json`.
/// Les modifiers déjà déclarés dans l'enum mais sans i18n sont silencieusement
/// ignorés (S3+ ajoutera leur description au fil de l'implémentation
/// gameplay).
class GriotBriefingOverlay extends StatelessWidget {
  const GriotBriefingOverlay({
    required this.modifiers,
    required this.isBoss,
    required this.onConfirm,
    this.firstEncounter = const <LevelModifier>{},
    super.key,
  });

  final Set<LevelModifier> modifiers;
  final bool isBoss;
  final VoidCallback onConfirm;

  /// Sous-ensemble de [modifiers] que le joueur rencontre pour la 1ère fois.
  /// Seules ces lignes afficheront la description complète ; les autres
  /// (déjà connues) n'affichent que le nom. Par défaut vide = toutes en
  /// version "rappel courte".
  final Set<LevelModifier> firstEncounter;

  @override
  Widget build(BuildContext context) {
    final entries = <_BriefingEntry>[];
    for (final m in modifiers) {
      final entry = _entryFor(m);
      if (entry != null) {
        entries.add(entry.copyWith(showDescription: firstEncounter.contains(m)));
      }
    }

    final accent = isBoss ? AppColors.orJour : AppColors.orSoleil;

    return Dialog(
      backgroundColor: AppColors.surfaceContainer,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: accent.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Kili en pleine escalade — visualise « la pente se raidit ».
            Image.asset(
              AppAssets.kiliClimb,
              width: 72,
              height: 53,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 8),
            // Badge « BOSS » — uniquement sur un stage boss, pastille dorée
            // pour signaler l'enjeu sans alourdir la card.
            if (isBoss) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.orJour.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.orJour.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  'game.briefing.boss_tag'.tr(),
                  style: AppTypography.labelXs.copyWith(
                    color: AppColors.orJour,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            // Eyebrow all-caps espacé, cohérent avec les autres popups
            // « Vert Nuit » (cf. DailyStreakDialog).
            Text(
              (isBoss
                      ? 'game.briefing.title_boss'
                      : 'game.briefing.title_normal')
                  .tr(),
              style: AppTypography.labelXs.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              isBoss
                  ? 'game.briefing.intro_boss'.tr()
                  : 'game.briefing.intro_normal'.tr(),
              style: AppTypography.bodyMd.copyWith(
                fontSize: 13,
                color: AppColors.texteSecondaire,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (entries.isNotEmpty) ...[
              const SizedBox(height: 16),
              // Card "défis" — chaque modifier sur sa propre ligne, séparateur
              // discret entre les lignes. Pas de scroll : on suppose <= 3
              // modifiers à la fois (résolveur S1) ; au-delà on basculera
              // sur ListView shrink-wrapped.
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.hairline),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (var i = 0; i < entries.length; i++) ...[
                      _BriefingRow(entry: entries[i]),
                      if (i < entries.length - 1) ...[
                        const SizedBox(height: 10),
                        Container(height: 1, color: AppColors.hairline),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            AppButton(
              label: 'game.briefing.cta'.tr(),
              fullWidth: true,
              onPressed: onConfirm,
            ),
          ],
        ),
      ),
    );
  }

  /// Mappe un [LevelModifier] sur sa représentation briefing. Retourne `null`
  /// pour les modifiers sans i18n (déclarés mais pas encore décrits côté
  /// joueur — cf. S3+).
  static _BriefingEntry? _entryFor(LevelModifier m) {
    switch (m) {
      case LevelModifier.reverse:
        return const _BriefingEntry(
          icon: Icons.swap_horiz_rounded,
          color: AppColors.rouge,
          i18nKey: 'reverse',
        );
      case LevelModifier.thinAir:
        return const _BriefingEntry(
          icon: Icons.air_rounded,
          color: AppColors.cielHauteur,
          i18nKey: 'thin_air',
        );
      case LevelModifier.wind:
        return const _BriefingEntry(
          icon: Icons.air_rounded,
          color: AppColors.cielHauteur,
          i18nKey: 'wind',
        );
      case LevelModifier.earthquake:
        return const _BriefingEntry(
          icon: Icons.terrain_rounded,
          color: AppColors.laterite,
          i18nKey: 'earthquake',
        );
      case LevelModifier.fog:
        return const _BriefingEntry(
          icon: Icons.cloud_rounded,
          color: AppColors.cielHauteur,
          i18nKey: 'fog',
        );
      case LevelModifier.shuffle:
        return const _BriefingEntry(
          icon: Icons.shuffle_rounded,
          color: AppColors.rouge,
          i18nKey: 'shuffle',
        );
      // Tous les modifiers ci-dessous sont déclarés dans l'enum mais leur
      // gameplay n'est pas encore implémenté visuellement — pas de briefing
      // tant que le joueur ne peut pas les ressentir en partie.
      case LevelModifier.mirage:
      case LevelModifier.lava:
      case LevelModifier.ice:
      case LevelModifier.rain:
      case LevelModifier.spirit:
      case LevelModifier.calabash:
      case LevelModifier.drumbeat:
      case LevelModifier.rockslide:
      case LevelModifier.chameleon:
      case LevelModifier.drySeason:
      case LevelModifier.pantherTrail:
      case LevelModifier.caveEcho:
        return null;
    }
  }
}

/// Ligne d'un modifier dans le briefing — icône colorée + nom (+ description
/// seulement à la première rencontre, contrôlée par `entry.showDescription`).
class _BriefingRow extends StatelessWidget {
  const _BriefingRow({required this.entry});

  final _BriefingEntry entry;

  @override
  Widget build(BuildContext context) {
    final keyBase = 'game.briefing.modifier.${entry.i18nKey}';
    return Row(
      crossAxisAlignment: entry.showDescription
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: <Widget>[
        // Pastille icône — fond teinté assorti à la couleur du badge in-game,
        // pour qu'on relie visuellement briefing et partie.
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: entry.color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: entry.color.withValues(alpha: 0.7),
              width: 1.2,
            ),
          ),
          child: Icon(entry.icon, size: 20, color: entry.color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '$keyBase.name'.tr(),
                style: AppTypography.bebas(
                  size: 14,
                  letterSpacing: 1.1,
                  color: entry.color,
                ),
              ),
              if (entry.showDescription) ...[
                const SizedBox(height: 2),
                Text(
                  '$keyBase.desc'.tr(),
                  style: AppTypography.crimson(
                    size: 13,
                    color: AppColors.textePrimaire,
                  ).copyWith(height: 1.35),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Données d'affichage d'un modifier dans le briefing.
class _BriefingEntry {
  const _BriefingEntry({
    required this.icon,
    required this.color,
    required this.i18nKey,
    this.showDescription = true,
  });

  final IconData icon;
  final Color color;

  /// Suffixe utilisé pour reconstruire les clés
  /// `game.briefing.modifier.<i18nKey>.name` et `.desc`.
  final String i18nKey;

  /// Affiche la description en plus du nom. Toggled à false aux rencontres
  /// répétées : le joueur connaît déjà le modifier, on ne fait que rappeler
  /// sa présence par l'icône et le nom.
  final bool showDescription;

  _BriefingEntry copyWith({bool? showDescription}) => _BriefingEntry(
    icon: icon,
    color: color,
    i18nKey: i18nKey,
    showDescription: showDescription ?? this.showDescription,
  );
}
