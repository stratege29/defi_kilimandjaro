import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Écran 05 — Overlay Échec (refonte world-class 2026, alignée VictoryView).
///
/// Ton non-punitif : révèle le mot, encourage à réessayer. Affiché via
/// [showDialog] avec fond noir à 92 % d'opacité.
///
/// **Architecture visuelle** : card centrée, accent rouge `error`.
/// - Griot triste 96pt en haut
/// - Mot-réponse révélé en Fraunces displayMd (rouge error)
/// - Explication courte Crimson italic
/// - Ligne d'encouragement Crimson italic
/// - CTA RÉESSAYER via AppButton.danger
///
/// **Bugfix** : wrap en `Material(transparency)` — sans Material ancestor
/// le `Text` rendait les soulignés debug "missing material".
class FailureView extends StatefulWidget {
  const FailureView({
    required this.devinette,
    required this.onRetry,
    super.key,
  });

  final Devinette devinette;

  /// Callback appelé quand l'utilisateur tape RÉESSAYER.
  final VoidCallback onRetry;

  @override
  State<FailureView> createState() => _FailureViewState();
}

class _FailureViewState extends State<FailureView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cardCtrl;
  late final Animation<double> _cardScale;

  @override
  void initState() {
    super.initState();
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

  String _truncatedExplanation(String text, {int maxChars = 120}) {
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars).trimRight()}…';
  }

  @override
  Widget build(BuildContext context) {
    // Material(transparency) : fournit le DefaultTextStyle ancestor pour
    // que les Text n'aient pas le souligné debug "missing material"
    // (même bugfix que VictoryView et MountainConquestView).
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: ScaleTransition(
          scale: _cardScale,
          child: _FailureCard(
            devinette: widget.devinette,
            truncatedExplanation: _truncatedExplanation(
              widget.devinette.explanation,
            ),
            onRetry: widget.onRetry,
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
    required this.truncatedExplanation,
    required this.onRetry,
  });

  final Devinette devinette;
  final String truncatedExplanation;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return Container(
      width: screenWidth * 0.88,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        // Palette 2026 — surface opaque + accent rouge `error`.
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.error, width: 1.5),
        boxShadow: <BoxShadow>[
          // Halo rouge subtil (signature failure).
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.18),
            blurRadius: 28,
          ),
          // Profondeur sous la card.
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Mascotte griot triste 96pt — pose empathique.
          Image.asset(AppAssets.griotSad, width: 96, height: 96),
          const SizedBox(height: 16),
          // Mot-réponse révélé — Fraunces displayMd, rouge error.
          Text(
            devinette.answer,
            style: AppTypography.displayMd.copyWith(color: AppColors.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          // "La réponse était {answer}" — caption.
          Text(
            'result.failure.answer_was'.tr(
              namedArgs: <String, String>{'answer': devinette.answer},
            ),
            textAlign: TextAlign.center,
            style: AppTypography.crimson(
              size: 13,
              color: AppColors.texteTertiaire,
            ),
          ),
          const SizedBox(height: 16),
          // Explication culturelle courte (2-3 lignes max via truncate).
          Text(
            truncatedExplanation,
            textAlign: TextAlign.center,
            style: AppTypography.crimson(
              size: 14,
              color: AppColors.texteSecondaire,
              style: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),
          // Ligne d'encouragement (« Tu y arriveras à la prochaine ! »).
          Text(
            'result.failure.consolation'.tr(),
            textAlign: TextAlign.center,
            style: AppTypography.crimson(
              size: 14,
              color: AppColors.texteTertiaire,
              style: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 24),
          // CTA RÉESSAYER — variant danger (errorSoft + border error).
          // Ton non-punitif : rouge subtil, pas un bouton agressif.
          AppButton(
            label: 'result.failure.retry'.tr(),
            onPressed: onRetry,
            variant: AppButtonVariant.danger,
            fullWidth: true,
          ),
        ],
      ),
    );
  }
}
