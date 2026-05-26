import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Overlay « Le griot t'avertit » affiché juste avant que le timer démarre
/// sur les niveaux qui contiennent des modifiers ou un boss.
///
/// Best practices (cf. discussion produit) :
/// - **Pause forcée** du timer pendant la lecture (côté `_GameViewState`)
/// - **Friction minimale** : un seul tap sur "Je suis prêt" suffit, et le
///   tap hors de la card ferme également l'overlay (barrierDismissible)
/// - **Cohérence narrative** : c'est le griot qui prévient (pas un "Niveau
///   Spécial!"), conforme au rôle de sage bienveillant
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
    super.key,
  });

  final Set<LevelModifier> modifiers;
  final bool isBoss;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final entries = <_BriefingEntry>[];
    for (final m in modifiers) {
      final entry = _entryFor(m);
      if (entry != null) entries.add(entry);
    }

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          color: AppColors.boisFonce,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (isBoss ? AppColors.orJour : AppColors.orSoleil)
                .withValues(alpha: 0.65),
            width: 1.5,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Avatar griot — 64pt centré, juste assez grand pour ancrer
            // l'identité narrative sans gaspiller la verticale.
            Image.asset(AppAssets.griotIdle, width: 64, height: 64),
            const SizedBox(height: 8),
            Text(
              'game.briefing.title'.tr(),
              style: AppTypography.bebas(
                size: 22,
                color: isBoss ? AppColors.orJour : AppColors.orSoleil,
                letterSpacing: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              isBoss
                  ? 'game.briefing.intro_boss'.tr()
                  : 'game.briefing.intro_normal'.tr(),
              style: AppTypography.crimson(
                size: 15,
                color: AppColors.textePrimaire,
                style: FontStyle.italic,
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
                  color: AppColors.bois.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.orSoleil.withValues(alpha: 0.25),
                  ),
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
                        Container(
                          height: 1,
                          color: AppColors.orSoleil.withValues(alpha: 0.15),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            // CTA "Je suis prêt" — pleine largeur, doré, hauteur 48pt
            // (au-dessus des 44pt iOS et 48dp Android pour tap confort).
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.vertClair,
                  foregroundColor: AppColors.ivoire,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 4,
                ),
                child: Text(
                  'game.briefing.cta'.tr(),
                  style: AppTypography.bebas(size: 18, letterSpacing: 1.5),
                ),
              ),
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

/// Ligne d'un modifier dans le briefing — icône colorée + nom + description.
class _BriefingRow extends StatelessWidget {
  const _BriefingRow({required this.entry});

  final _BriefingEntry entry;

  @override
  Widget build(BuildContext context) {
    final keyBase = 'game.briefing.modifier.${entry.i18nKey}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 2),
              Text(
                '$keyBase.desc'.tr(),
                style: AppTypography.crimson(
                  size: 13,
                  color: AppColors.textePrimaire,
                ).copyWith(height: 1.35),
              ),
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
  });

  final IconData icon;
  final Color color;

  /// Suffixe utilisé pour reconstruire les clés
  /// `game.briefing.modifier.<i18nKey>.name` et `.desc`.
  final String i18nKey;
}
