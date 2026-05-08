import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/domain/entities/devinette.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Écran 05 — Overlay Échec (cf. maquette p.7).
///
/// Ton non-punitif : révèle le mot, encourage à réessayer.
/// Affiché via [showDialog] avec fond noir à 92 % d'opacité.
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

    _cardScale = Tween<double>(begin: 0.7, end: 1).animate(
      CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _cardCtrl.dispose();
    super.dispose();
  }

  String _subjectEmoji() {
    final tags = widget.devinette.tags;
    if (tags.any((t) => t.contains('cuisine') || t.contains('food'))) {
      return '🍲';
    }
    if (tags.any((t) => t.contains('nature') || t.contains('plante'))) {
      return '🌿';
    }
    if (tags.any((t) => t.contains('animal'))) return '🦁';
    if (tags.any((t) => t.contains('musique') || t.contains('music'))) {
      return '🎵';
    }
    if (tags.any((t) => t.contains('art') || t.contains('tissu'))) {
      return '🎨';
    }
    return '🌍';
  }

  String _truncatedExplanation(String text, {int maxChars = 120}) {
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars).trimRight()}…';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ScaleTransition(
        scale: _cardScale,
        child: _FailureCard(
          devinette: widget.devinette,
          subjectEmoji: _subjectEmoji(),
          truncatedExplanation: _truncatedExplanation(widget.devinette.explanation),
          onRetry: widget.onRetry,
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
    required this.subjectEmoji,
    required this.truncatedExplanation,
    required this.onRetry,
  });

  final Devinette devinette;
  final String subjectEmoji;
  final String truncatedExplanation;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return Container(
      width: screenWidth * 0.88,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.boisFonce.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.rouge, width: 3),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Griot mascot — empathetic consolation pose.
            Image.asset(
              AppAssets.griotSad,
              width: 140,
              height: 140,
            ),
            const SizedBox(height: 12),
            // Subject circle — red border.
            _SubjectCircle(emoji: subjectEmoji, borderColor: AppColors.rouge),
            const SizedBox(height: 16),
            // Revealed answer.
            Text(
              devinette.answer,
              style: AppTypography.bebas(size: 42, color: AppColors.rouge),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // "La réponse était {answer}"
            Text(
              'result.failure.answer_was'
                  .tr(namedArgs: <String, String>{'answer': devinette.answer}),
              style: AppTypography.crimson(
                size: 15,
                color: AppColors.ivoire.withValues(alpha: 0.85),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            // Short explanation.
            Text(
              truncatedExplanation,
              textAlign: TextAlign.center,
              style: AppTypography.crimson(
                size: 15,
                color: AppColors.ivoire.withValues(alpha: 0.80),
                style: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 16),
            // Consolation proverb box.
            _ProverbBox(proverb: devinette.proverb),
            const SizedBox(height: 10),
            // Encouragement line.
            Text(
              'result.failure.consolation'.tr(),
              style: AppTypography.crimson(
                style: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Retry button.
            _RetryButton(onTap: onRetry),
          ],
        ),
      ),
    );
  }
}

class _SubjectCircle extends StatelessWidget {
  const _SubjectCircle({
    required this.emoji,
    required this.borderColor,
  });

  final String emoji;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.boisFonce,
        border: Border.all(color: borderColor, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 56)),
    );
  }
}

class _ProverbBox extends StatelessWidget {
  const _ProverbBox({required this.proverb});

  final String proverb;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.rouge.withValues(alpha: 0.7),
          width: 1.5,
        ),
      ),
      child: Text(
        '"$proverb"',
        textAlign: TextAlign.center,
        style: AppTypography.crimson(
          color: AppColors.tagline,
          style: FontStyle.italic,
        ),
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.rouge.withValues(alpha: 0.70),
          foregroundColor: AppColors.ivoire,
          minimumSize: const Size(240, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
        ),
        child: Text(
          'result.failure.retry'.tr(),
          style: AppTypography.bebas(size: 18),
        ),
      ),
    );
  }
}
