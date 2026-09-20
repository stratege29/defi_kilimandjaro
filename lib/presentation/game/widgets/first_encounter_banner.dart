import 'dart:async';

import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/level_modifier.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Bandeau compact **non modal** de première rencontre d'un modificateur.
///
/// Remplace l'ancien briefing plein écran du griot : une ligne par
/// modificateur nouveau (icône + nom + description courte, clés i18n
/// `game.briefing.modifier.<nom>`), affichée [displayDuration] puis repliée
/// d'elle-même ; un tap le replie plus tôt. Le widget gère sa propre
/// animation et appelle [onDismissed] **exactement une fois** (timer ou tap)
/// — c'est le parent qui met le timer de jeu en pause pendant l'affichage et
/// le reprend dans ce callback.
///
/// Les modificateurs sans i18n (déclarés dans l'enum mais sans gameplay
/// visible) sont ignorés ; si aucun ne reste, le bandeau est vide et se
/// replie immédiatement. Le boss n'a pas de bandeau (badge d'en-tête suffit).
class FirstEncounterBanner extends StatefulWidget {
  const FirstEncounterBanner({
    required this.modifiers,
    required this.onDismissed,
    this.displayDuration = const Duration(seconds: 3),
    super.key,
  });

  /// Modificateurs rencontrés pour la première fois (déjà filtrés par
  /// `PlayerProgress.encounteredModifiers` côté vue).
  final Set<LevelModifier> modifiers;

  /// Appelé une seule fois quand le bandeau se replie (auto ou tap).
  final VoidCallback onDismissed;

  /// Durée d'affichage avant repli automatique.
  final Duration displayDuration;

  /// Sous-ensemble de [modifiers] qui a une description joueur. Utile au
  /// parent pour ne pas mettre le timer en pause pour un bandeau vide.
  static Set<LevelModifier> describable(Set<LevelModifier> modifiers) =>
      modifiers.where((m) => _entryFor(m) != null).toSet();

  /// Mappe un [LevelModifier] sur icône / couleur / clé i18n. `null` pour les
  /// modificateurs non décrits côté joueur (cf. ancien briefing).
  static _BannerEntry? _entryFor(LevelModifier m) {
    switch (m) {
      case LevelModifier.reverse:
        return const _BannerEntry(
          icon: Icons.swap_horiz_rounded,
          color: AppColors.rouge,
          i18nKey: 'reverse',
        );
      case LevelModifier.thinAir:
        return const _BannerEntry(
          icon: Icons.air_rounded,
          color: AppColors.cielHauteur,
          i18nKey: 'thin_air',
        );
      case LevelModifier.wind:
        return const _BannerEntry(
          icon: Icons.air_rounded,
          color: AppColors.cielHauteur,
          i18nKey: 'wind',
        );
      case LevelModifier.earthquake:
        return const _BannerEntry(
          icon: Icons.terrain_rounded,
          color: AppColors.laterite,
          i18nKey: 'earthquake',
        );
      case LevelModifier.fog:
        return const _BannerEntry(
          icon: Icons.cloud_rounded,
          color: AppColors.cielHauteur,
          i18nKey: 'fog',
        );
      case LevelModifier.shuffle:
        return const _BannerEntry(
          icon: Icons.shuffle_rounded,
          color: AppColors.rouge,
          i18nKey: 'shuffle',
        );
      case LevelModifier.mirage:
        return const _BannerEntry(
          icon: Icons.wb_sunny_rounded,
          color: AppColors.savanneOcre,
          i18nKey: 'mirage',
        );
      case LevelModifier.rain:
        return const _BannerEntry(
          icon: Icons.water_drop_rounded,
          color: AppColors.info,
          i18nKey: 'rain',
        );
      case LevelModifier.spirit:
        return const _BannerEntry(
          icon: Icons.auto_awesome_rounded,
          color: AppColors.esprit,
          i18nKey: 'spirit',
        );
      case LevelModifier.lava:
      case LevelModifier.ice:
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

  @override
  State<FirstEncounterBanner> createState() => _FirstEncounterBannerState();
}

class _FirstEncounterBannerState extends State<FirstEncounterBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  Timer? _autoTimer;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, -0.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
    _autoTimer = Timer(widget.displayDuration, _dismiss);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_dismissed) return;
    _dismissed = true;
    _autoTimer?.cancel();
    await _ctrl.reverse();
    if (!mounted) return;
    widget.onDismissed();
  }

  @override
  Widget build(BuildContext context) {
    final entries = <_BannerEntry>[
      for (final m in widget.modifiers)
        if (FirstEncounterBanner._entryFor(m) case final e?) e,
    ];
    // Une fois replié, ne capte plus les taps (le tracé passe dessous).
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => IgnorePointer(
        ignoring: _dismissed,
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(position: _slide, child: child),
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismiss,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.hairline),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var i = 0; i < entries.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: 6),
                _BannerRow(entry: entries[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Une ligne : pastille icône + « Nom — description courte ».
class _BannerRow extends StatelessWidget {
  const _BannerRow({required this.entry});

  final _BannerEntry entry;

  @override
  Widget build(BuildContext context) {
    final keyBase = 'game.briefing.modifier.${entry.i18nKey}';
    return Row(
      children: <Widget>[
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: entry.color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: entry.color.withValues(alpha: 0.7),
              width: 1.2,
            ),
          ),
          child: Icon(entry.icon, size: 16, color: entry.color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: '$keyBase.name'.tr(),
                  style: AppTypography.bebas(
                    size: 13,
                    letterSpacing: 1.1,
                    color: entry.color,
                  ),
                ),
                TextSpan(
                  text: ' — ${'$keyBase.desc'.tr()}',
                  style: AppTypography.crimson(size: 13),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Données d'affichage d'un modificateur dans le bandeau.
class _BannerEntry {
  const _BannerEntry({
    required this.icon,
    required this.color,
    required this.i18nKey,
  });

  final IconData icon;
  final Color color;

  /// Suffixe des clés `game.briefing.modifier.<i18nKey>.name` / `.desc`.
  final String i18nKey;
}
