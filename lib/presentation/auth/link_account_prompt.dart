import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/local/link_prompt_gate.dart';
import 'package:defi_kilimandjaro/data/repositories/auth_repository.dart';
import 'package:defi_kilimandjaro/presentation/profile/account_controller.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Propose, à un moment clé, de lier le compte anonyme à Google/Apple —
/// si et seulement si la session est anonyme ET que le cadenceur
/// ([LinkPromptGate]) l'autorise (cadence douce, snooze, plafond).
///
/// Best-effort et non bloquant : à appeler dans un `addPostFrameCallback`
/// ou après une autre interaction. Ne lève jamais ; un échec silencieux ne
/// dégrade pas le flux de jeu.
///
/// Exemple :
/// ```dart
/// await maybeShowLinkAccountPrompt(
///   context, ref, LinkPromptTrigger.mountainComplete,
/// );
/// ```
Future<void> maybeShowLinkAccountPrompt(
  BuildContext context,
  WidgetRef ref,
  LinkPromptTrigger trigger,
) async {
  // 1. Jamais pour un compte déjà lié.
  if (!ref.read(isAnonymousProvider)) return;

  // 2. Respecter la cadence (72 h / snooze 7 j / plafond 3).
  final gate = ref.read(linkPromptGateProvider);
  if (!gate.shouldShow()) return;

  // 3. Armer la fenêtre AVANT d'afficher (évite tout double-déclenchement
  //    si deux moments clés surviennent dans la même frame).
  await gate.recordShown();
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _LinkAccountSheet(trigger: trigger),
  );
}

String _titleKey(LinkPromptTrigger trigger) {
  switch (trigger) {
    case LinkPromptTrigger.mountainComplete:
      return 'auth.link_prompt.title_mountain';
    case LinkPromptTrigger.duelFinished:
      return 'auth.link_prompt.title_duel';
    case LinkPromptTrigger.purchase:
      return 'auth.link_prompt.title_purchase';
    case LinkPromptTrigger.streak:
      return 'auth.link_prompt.title_streak';
  }
}

class _LinkAccountSheet extends ConsumerWidget {
  const _LinkAccountSheet({required this.trigger});

  final LinkPromptTrigger trigger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref
      // Ferme la feuille dès que la liaison aboutit (passage non-anonyme).
      ..listen<bool>(isAnonymousProvider, (prev, isAnon) {
        if ((prev ?? false) && !isAnon && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      })
      // Réutilise le contrôleur de compte pour le feedback (erreur/bascule).
      ..listen<AccountUiState>(accountControllerProvider, (prev, next) {
        if (next.error != null) {
          final detail = next.errorDetail;
          final msg = (detail != null && detail.isNotEmpty)
              ? '${next.error!.tr()} ($detail)'
              : next.error!.tr();
          ScaffoldMessenger.of(context)
              .showSnackBar(_snack(msg, isError: true));
          ref.read(accountControllerProvider.notifier).clearMessages();
        } else if (next.notice != null) {
          ScaffoldMessenger.of(context).showSnackBar(_snack(next.notice!.tr()));
          ref.read(accountControllerProvider.notifier).clearMessages();
        }
      });

    final busy = ref.watch(accountControllerProvider).isBusy;
    final notifier = ref.read(accountControllerProvider.notifier);

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.orJour.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              _titleKey(trigger).tr(),
              style: AppTypography.headingMd,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'auth.link_prompt.body'.tr(),
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.texteSecondaire),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'profile.account.link_google'.tr(),
              variant: AppButtonVariant.soft,
              icon: Icons.account_circle_outlined,
              fullWidth: true,
              loading: busy,
              onPressed: busy ? null : notifier.linkWithGoogle,
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'profile.account.link_apple'.tr(),
              variant: AppButtonVariant.soft,
              icon: Icons.apple,
              fullWidth: true,
              onPressed: busy ? null : notifier.linkWithApple,
            ),
            const SizedBox(height: 8),
            AppButton(
              label: 'auth.link_prompt.later'.tr(),
              variant: AppButtonVariant.ghost,
              fullWidth: true,
              onPressed: busy
                  ? null
                  : () async {
                      await ref.read(linkPromptGateProvider).recordSnoozed();
                      if (context.mounted) Navigator.of(context).pop();
                    },
            ),
          ],
        ),
      ),
    );
  }

  static SnackBar _snack(String message, {bool isError = false}) => SnackBar(
        backgroundColor: isError ? AppColors.error : AppColors.surfaceContainer,
        behavior: SnackBarBehavior.floating,
        content: Text(
          message,
          style: AppTypography.bodyMd.copyWith(color: AppColors.textePrimaire),
        ),
      );
}
