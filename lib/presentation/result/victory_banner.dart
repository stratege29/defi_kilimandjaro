import 'dart:async';

import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/presentation/result/devinette_explanation.dart';
import 'package:defi_kilimandjaro/presentation/result/reward_lines.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Bannière de victoire **compacte** pour les niveaux ordinaires (ni boss, ni
/// défi du jour, ni dernier niveau d'une montagne — ceux-là gardent
/// `VictoryView`).
///
/// Bandeau en bas d'écran : mot-réponse, étoiles, « +N cauris », lignes série
/// / sans faute / à main levée. **Auto-avance** après [autoAdvanceDelay] ; un
/// tap n'importe où avance tout de suite. Le chevron déplie l'explication
/// culturelle et **annule** l'auto-avance (le joueur tape alors SUIVANT). Le
/// bouton ×2 (rewarded « Doubler ») annule aussi l'auto-avance et déclenche
/// [doubleReward] ; le flux de crédit reste celui de `VictoryView`.
///
/// Affichée via `showDialog` par `GameView` : [onNext] ferme le dialog et
/// enchaîne (interstitielle, niveau suivant) — appelé **exactement une fois**.
/// Sans dépendance Riverpod (éligibilité rewarded calculée par l'appelant)
/// pour rester testable en widget test pur.
class VictoryBanner extends StatefulWidget {
  const VictoryBanner({
    required this.devinette,
    required this.caurisAwarded,
    required this.onNext,
    this.starsEarned = 0,
    this.freehandBonus = 0,
    this.perfectBonus = 0,
    this.comboStreak = 0,
    this.comboMultiplier = 1.0,
    this.doubleReward,
    this.autoAdvanceDelay = const Duration(milliseconds: 1800),
    this.devinettes,
    super.key,
  });

  final Devinette devinette;

  /// Toutes les devinettes du niveau (rafale : 3 mots, duo : 2 mots).
  /// `null` = niveau à un seul mot, [devinette] seule. La section dépliée
  /// affiche l'explication de chacune (mot en gras + explication).
  final List<Devinette>? devinettes;

  /// Devinettes à expliquer, principale seule par défaut.
  List<Devinette> get allDevinettes => devinettes ?? <Devinette>[devinette];

  /// Récompense de base créditée (après tier et multiplicateur de série).
  /// Base du bouton ×2.
  final int caurisAwarded;

  /// Étoiles obtenues (1-3).
  final int starsEarned;

  /// Bonus « À main levée » déjà inclus dans le solde (0 = pas de ligne).
  final int freehandBonus;

  /// Bonus « Sans faute » déjà inclus dans le solde (0 = pas de ligne).
  final int perfectBonus;

  /// Longueur de la série intra-session (victoire courante incluse).
  final int comboStreak;

  /// Multiplicateur de série appliqué à [caurisAwarded] (1.0 = pas de ligne).
  final double comboMultiplier;

  /// Rewarded « Doubler » : `null` = non éligible (bouton absent). Retourne
  /// `true` si la pub a été vue jusqu'au bout et le bonus crédité.
  final Future<bool> Function()? doubleReward;

  /// Délai avant l'avance automatique.
  final Duration autoAdvanceDelay;

  /// Appelé une seule fois : auto-avance, tap, ou SUIVANT.
  final VoidCallback onNext;

  @override
  State<VictoryBanner> createState() => _VictoryBannerState();
}

class _VictoryBannerState extends State<VictoryBanner>
    with TickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slide;
  late final AnimationController _caurisCtrl;
  late final Animation<int> _caurisAnim;

  Timer? _autoTimer;
  bool _advanced = false;

  /// Vrai quand l'auto-avance est annulée (explication dépliée ou ×2) : le
  /// bandeau attend alors SUIVANT et un tap hors bouton ne fait plus avancer.
  bool _holding = false;
  bool _expanded = false;
  bool _doubling = false;
  bool _doubled = false;

  int get _caurisTotal =>
      widget.caurisAwarded + widget.freehandBonus + widget.perfectBonus;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
    _slide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic),
    );
    _caurisCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _caurisAnim = IntTween(begin: 0, end: _caurisTotal).animate(
      CurvedAnimation(parent: _caurisCtrl, curve: Curves.easeOutCubic),
    );
    _autoTimer = Timer(widget.autoAdvanceDelay, _advance);
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _slideCtrl.dispose();
    _caurisCtrl.dispose();
    super.dispose();
  }

  void _advance() {
    if (_advanced) return;
    _advanced = true;
    _autoTimer?.cancel();
    widget.onNext();
  }

  /// Annule l'auto-avance : le joueur reprend la main (SUIVANT).
  void _hold() {
    _autoTimer?.cancel();
    if (_holding) return;
    setState(() => _holding = true);
  }

  void _toggleExplanation() {
    _hold();
    setState(() => _expanded = !_expanded);
  }

  Future<void> _handleDouble() async {
    final double = widget.doubleReward;
    if (double == null || _doubling || _doubled) return;
    _hold();
    setState(() => _doubling = true);
    final got = await double();
    if (!mounted) return;
    setState(() {
      _doubling = false;
      _doubled = got;
    });
    if (got) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'result.victory.double_done'.tr(
              namedArgs: <String, String>{'cauris': '${widget.caurisAwarded}'},
            ),
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.orJour,
          duration: const Duration(milliseconds: 1500),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDouble = widget.doubleReward != null && !_doubled;
    // Material(transparency) : DefaultTextStyle ancestor pour les Text.
    return Material(
      type: MaterialType.transparency,
      // Tap n'importe où = avancer tout de suite (sauf quand le joueur a
      // repris la main via le chevron ou ×2).
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _holding ? null : _advance,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SlideTransition(
            position: _slide,
            child: SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                constraints: const BoxConstraints(maxWidth: 480),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.4),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _HeadlineRow(
                      answer: widget.devinette.answer,
                      starsEarned: widget.starsEarned,
                      expanded: _expanded,
                      onToggle: _toggleExplanation,
                    ),
                    const SizedBox(height: 10),
                    _RewardRow(
                      caurisAnim: _caurisAnim,
                      doubleButton: canDouble
                          ? _DoubleChip(
                              loading: _doubling,
                              onTap: _doubling ? null : _handleDouble,
                            )
                          : null,
                    ),
                    if (widget.comboMultiplier > 1 ||
                        widget.perfectBonus > 0 ||
                        widget.freehandBonus > 0) ...<Widget>[
                      const SizedBox(height: 8),
                      RewardBonusLines(
                        comboStreak: widget.comboStreak,
                        comboMultiplier: widget.comboMultiplier,
                        perfectBonus: widget.perfectBonus,
                        freehandBonus: widget.freehandBonus,
                        alignment: WrapAlignment.start,
                      ),
                    ],
                    // Explication culturelle dépliée + CTA SUIVANT quand le
                    // joueur a repris la main.
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                      child: _holding
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  if (_expanded) ...<Widget>[
                                    for (final d in widget.allDevinettes)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: DevinetteExplanation(
                                          devinette: d,
                                          // Un seul mot : il est déjà dans
                                          // le titre, pas de rappel.
                                          showAnswer:
                                              widget.allDevinettes.length > 1,
                                        ),
                                      ),
                                  ],
                                  AppButton(
                                    label: 'result.victory.next'.tr(),
                                    onPressed: _advance,
                                    fullWidth: true,
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Étoiles + mot-réponse + chevron « explication ».
class _HeadlineRow extends StatelessWidget {
  const _HeadlineRow({
    required this.answer,
    required this.starsEarned,
    required this.expanded,
    required this.onToggle,
  });

  final String answer;
  final int starsEarned;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  for (var i = 1; i <= 3; i++) ...<Widget>[
                    if (i > 1) const SizedBox(width: 3),
                    Opacity(
                      opacity: i <= starsEarned ? 1 : 0.22,
                      child: Image.asset(
                        AppAssets.iconStarGold,
                        width: 16,
                        height: 16,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                answer.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.displaySm.copyWith(fontSize: 26),
              ),
            ],
          ),
        ),
        // Chevron « explication » — cible 44pt.
        IconButton(
          key: const ValueKey<String>('victory_banner_explain'),
          onPressed: onToggle,
          tooltip: 'Explication',
          icon: AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(
              Icons.expand_more_rounded,
              size: 28,
              color: AppColors.texteSecondaire,
            ),
          ),
        ),
      ],
    );
  }
}

/// Chip « +N cauris » animé + bouton ×2 optionnel.
class _RewardRow extends StatelessWidget {
  const _RewardRow({required this.caurisAnim, required this.doubleButton});

  final Animation<int> caurisAnim;
  final Widget? doubleButton;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.orJour.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: AppColors.orJour.withValues(alpha: 0.45),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CaurisIcon(),
              const SizedBox(width: 6),
              AnimatedBuilder(
                animation: caurisAnim,
                builder: (_, __) => Text(
                  '+${caurisAnim.value}',
                  style: AppTypography.headingMd.copyWith(
                    color: AppColors.orJour,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'CAURIS',
                style: AppTypography.labelXs.copyWith(
                  color: AppColors.orJour.withValues(alpha: 0.75),
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        if (doubleButton != null) doubleButton!,
      ],
    );
  }
}

/// Petit bouton « ×2 ▶ » (rewarded « Doubler ») — filet doré discret.
class _DoubleChip extends StatelessWidget {
  const _DoubleChip({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey<String>('victory_banner_double'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: AppColors.orJour.withValues(alpha: 0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.orJour),
                ),
              )
            else
              const Icon(
                Icons.play_circle_outline_rounded,
                size: 16,
                color: AppColors.orJour,
              ),
            const SizedBox(width: 6),
            Text(
              '×2',
              style: AppTypography.headingSm.copyWith(color: AppColors.orJour),
            ),
          ],
        ),
      ),
    );
  }
}
