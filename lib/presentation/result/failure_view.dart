import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:defi_kilimandjaro/presentation/widgets/dashed_button.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Écran 05 — Overlay Échec (refonte world-class 2026, alignée VictoryView).
///
/// **Deux modes d'affichage**, contrôlés par [answerRevealed] :
/// - `answerRevealed: true` (default, rétro-compatible) — comportement
///   d'amorçage : la réponse est révélée gratuitement, on encourage à
///   réessayer. Utilisé en zone d'amorçage (Tier 1) ET sur les niveaux
///   T2+ où le joueur a déjà payé le reveal ou cumulé 3 échecs.
/// - `answerRevealed: false` — la réponse est **masquée**. L'explication
///   culturelle reste affichée (la promesse pédagogique survit), et deux
///   boutons cohabitent : RÉESSAYER (gratuit, primaire danger) et
///   « Voir la réponse — N 🐚 » (achat cauris, secondaire).
///
/// Le state local `_revealed` permet à l'overlay de basculer en mode
/// révélé après un achat réussi sans devoir recréer le dialog.
///
/// Affiché via [showDialog] avec fond noir à 92 % d'opacité.
///
/// **Bugfix** : wrap en `Material(transparency)` — sans Material ancestor
/// le `Text` rendait les soulignés debug "missing material".
class FailureView extends StatefulWidget {
  const FailureView({
    required this.devinette,
    required this.onRetry,
    this.answerRevealed = true,
    this.revealCost,
    this.onPurchaseReveal,
    this.canAffordReveal = false,
    this.onSkip,
    super.key,
  });

  final Devinette devinette;

  /// Callback appelé quand l'utilisateur tape RÉESSAYER.
  final VoidCallback onRetry;

  /// Anti-tilt : callback du skip gratuit. Quand non-`null`, une CTA
  /// tertiaire « Passer (gratuit) » est affichée sous RÉESSAYER. Le caller
  /// ne la fournit qu'au-delà du seuil `kFreeSkipLossThreshold` de défaites
  /// consécutives sur cette devinette. `null` = pas de skip proposé.
  final VoidCallback? onSkip;

  /// Mode d'affichage initial. `true` (default) reproduit le comportement
  /// historique. `false` masque la réponse et active le bouton d'achat.
  final bool answerRevealed;

  /// Coût en cauris pour révéler la réponse. Ignoré si [answerRevealed]
  /// est `true` ou si [onPurchaseReveal] est `null`.
  final int? revealCost;

  /// Tente l'achat du reveal côté repository. Doit retourner `true` si
  /// l'achat a réussi (cauris débités), `false` si solde insuffisant.
  /// Si `null`, aucun bouton d'achat n'est affiché.
  final Future<bool> Function()? onPurchaseReveal;

  /// Pré-évaluation côté caller : `true` si le solde du joueur permet
  /// l'achat. Quand `false`, le bouton "Voir la réponse" est désactivé
  /// visuellement (opacity 0.38, no tap). Le tap reste bloqué en sécurité
  /// via le check côté [onPurchaseReveal].
  final bool canAffordReveal;

  @override
  State<FailureView> createState() => _FailureViewState();
}

class _FailureViewState extends State<FailureView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cardCtrl;
  late final Animation<double> _cardScale;
  late bool _revealed;
  bool _purchasePending = false;

  @override
  void initState() {
    super.initState();
    _revealed = widget.answerRevealed;
    _cardCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    _cardScale = Tween<double>(
      begin: 0.7,
      end: 1,
    ).animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _cardCtrl.dispose();
    super.dispose();
  }

  Future<void> _handlePurchase() async {
    final purchase = widget.onPurchaseReveal;
    if (purchase == null || _purchasePending) return;
    setState(() => _purchasePending = true);
    final ok = await purchase();
    if (!mounted) return;
    setState(() {
      _purchasePending = false;
      if (ok) _revealed = true;
    });
    if (!ok && widget.revealCost != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'result.failure.reveal_insufficient'.tr(
              namedArgs: <String, String>{
                'cost': widget.revealCost!.toString(),
              },
            ),
            style: AppTypography.bodyMd.copyWith(color: AppColors.textePrimaire),
          ),
          backgroundColor: AppColors.surfaceContainer,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: ScaleTransition(
          scale: _cardScale,
          child: _FailureCard(
            devinette: widget.devinette,
            onRetry: widget.onRetry,
            revealed: _revealed,
            revealCost: widget.revealCost,
            canAffordReveal: widget.canAffordReveal && !_purchasePending,
            purchasePending: _purchasePending,
            onPurchaseReveal:
                widget.onPurchaseReveal == null ? null : _handlePurchase,
            onSkip: widget.onSkip,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card widget
// ---------------------------------------------------------------------------

class _FailureCard extends StatelessWidget {
  const _FailureCard({
    required this.devinette,
    required this.onRetry,
    required this.revealed,
    required this.canAffordReveal,
    required this.purchasePending,
    this.revealCost,
    this.onPurchaseReveal,
    this.onSkip,
  });

  final Devinette devinette;
  final VoidCallback onRetry;
  final bool revealed;
  final int? revealCost;
  final bool canAffordReveal;
  final bool purchasePending;
  final VoidCallback? onPurchaseReveal;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return Container(
      width: screenWidth * 0.88,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        // Vert Nuit : bordure sémantique « échec » en hairline rouge teinté,
        // pas de rouge plein ni de glow. Seule une ombre noire diffuse porte
        // l'élévation.
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 60,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Image.asset(AppAssets.griotSad, width: 96, height: 96),
          const SizedBox(height: 16),
          if (revealed) ..._revealedHeader() else ..._hiddenHeader(),
          const SizedBox(height: 16),
          // Explication culturelle — toujours affichée, dans les 2 modes.
          // C'est la promesse "tu apprends quelque chose" qui survit même
          // quand la réponse reste masquée.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: SingleChildScrollView(
              child: Text(
                devinette.explanation,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMd.copyWith(
                  color: AppColors.textePrimaire,
                  height: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'result.failure.consolation'.tr(),
            textAlign: TextAlign.center,
            style: AppTypography.crimson(
              size: 15,
              color: AppColors.texteSecondaire,
              style: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 24),
          AppButton(
            label: 'result.failure.retry'.tr(),
            onPressed: onRetry,
            variant: AppButtonVariant.danger,
            fullWidth: true,
          ),
          if (!revealed && onPurchaseReveal != null && revealCost != null) ...[
            const SizedBox(height: 10),
            // Filet anti-blocage façon maquette `.double` : bordure pointillée
            // hairline neutre, coût en cauris en trailing — n'éclipse pas le
            // CTA RÉESSAYER primaire au-dessus.
            DashedButton(
              label: 'result.failure.reveal_button'.tr(
                namedArgs: <String, String>{
                  'cost': revealCost!.toString(),
                },
              ),
              onTap: canAffordReveal ? onPurchaseReveal : null,
              borderColor: AppColors.hairline,
              textColor: AppColors.texteSecondaire,
              trailing: purchasePending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.texteSecondaire,
                      ),
                    )
                  : const CaurisIcon(size: 16),
            ),
          ],
          // Anti-tilt : skip gratuit après N défaites consécutives sur
          // cette devinette. CTA tertiaire « ghost » — désamorce la
          // frustration sans éclipser RÉESSAYER ni le reveal.
          if (onSkip != null) ...[
            const SizedBox(height: 10),
            AppButton(
              label: 'result.failure.skip_free'.tr(),
              onPressed: onSkip,
              variant: AppButtonVariant.ghost,
              fullWidth: true,
            ),
          ],
        ],
      ),
    );
  }

  /// En-tête en mode "réponse révélée" (comportement historique).
  ///
  /// Maquette `.pp.lose` : petit label all-caps tertiaire « LA RÉPONSE ÉTAIT »
  /// AU-DESSUS du mot rouge prestige, pas en légende dessous.
  List<Widget> _revealedHeader() {
    return <Widget>[
      Text(
        'result.failure.answer_was_label'.tr().toUpperCase(),
        textAlign: TextAlign.center,
        style: AppTypography.labelXs.copyWith(
          color: AppColors.texteTertiaire,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        devinette.answer.toUpperCase(),
        style: AppTypography.displayMd.copyWith(
          color: AppColors.error,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.5),
              offset: const Offset(0, 2),
              blurRadius: 4,
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    ];
  }

  /// En-tête en mode "réponse masquée" (T2+ pré-achat, échecs < 3).
  /// Affiche "Mot caché" en displayMd rouge + hint italique sur fond
  /// secondaire — préserve l'asymétrie visuelle "ça pique mais ce n'est
  /// pas la fin".
  List<Widget> _hiddenHeader() {
    return <Widget>[
      Text(
        'result.failure.answer_hidden_title'.tr(),
        style: AppTypography.displayMd.copyWith(color: AppColors.error),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(
        'result.failure.answer_hidden_hint'.tr(),
        textAlign: TextAlign.center,
        style: AppTypography.crimson(
          size: 13,
          color: AppColors.texteSecondaire,
          style: FontStyle.italic,
        ),
      ),
    ];
  }
}
