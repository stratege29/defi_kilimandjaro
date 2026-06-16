import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/auth_repository.dart';
import 'package:defi_kilimandjaro/presentation/profile/account_controller.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_card.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Section « Compte » du profil — liaison optionnelle Google/Apple.
///
/// - **Anonyme** : invite + boutons « Continuer avec Google / Apple ».
/// - **Lié** : fournisseur + email, déconnexion, suppression de compte.
///
/// Anonyme-first : aucune fonctionnalité n'est verrouillée. Lier un compte
/// préserve l'uid (donc ELO, wallet, duels), et permet la synchro multi-
/// appareils + la récupération.
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AccountUiState>(accountControllerProvider, (prev, next) {
      final messenger = ScaffoldMessenger.of(context);
      if (next.error != null) {
        final detail = next.errorDetail;
        final msg = (detail != null && detail.isNotEmpty)
            ? '${next.error!.tr()} ($detail)'
            : next.error!.tr();
        messenger.showSnackBar(_snack(msg, isError: true));
        ref.read(accountControllerProvider.notifier).clearMessages();
      } else if (next.notice != null) {
        messenger.showSnackBar(_snack(next.notice!.tr()));
        ref.read(accountControllerProvider.notifier).clearMessages();
      }
    });

    final user = ref.watch(authStateProvider).valueOrNull;
    final isAnon = user?.isAnonymous ?? true;
    final ui = ref.watch(accountControllerProvider);

    return AppCard(
      child: isAnon
          ? _Anonymous(busy: ui.isBusy)
          : _Linked(
              provider: ref.watch(currentAccountProviderProvider),
              email: user?.email,
              busy: ui.isBusy,
            ),
    );
  }

  static SnackBar _snack(String message, {bool isError = false}) => SnackBar(
        backgroundColor:
            isError ? AppColors.error : AppColors.surfaceContainer,
        behavior: SnackBarBehavior.floating,
        content: Text(
          message,
          style: AppTypography.bodyMd.copyWith(color: AppColors.textePrimaire),
        ),
      );
}

class _Anonymous extends ConsumerWidget {
  const _Anonymous({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(accountControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'profile.account.anonymous_prompt'.tr(),
          style:
              AppTypography.bodySm.copyWith(color: AppColors.texteSecondaire),
        ),
        const SizedBox(height: 16),
        AppButton(
          label: 'profile.account.link_google'.tr(),
          variant: AppButtonVariant.soft,
          icon: Icons.account_circle_outlined,
          fullWidth: true,
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
        if (busy) ...[
          const SizedBox(height: 16),
          const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
      ],
    );
  }
}

class _Linked extends ConsumerWidget {
  const _Linked({
    required this.provider,
    required this.email,
    required this.busy,
  });

  final AccountProvider provider;
  final String? email;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(accountControllerProvider.notifier);
    final providerLabel = provider == AccountProvider.apple ? 'Apple' : 'Google';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.verified_user_outlined, color: AppColors.success),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'profile.account.linked_via'.tr(args: [providerLabel]),
                    style: AppTypography.headingSm,
                  ),
                  if (email != null && email!.isNotEmpty)
                    Text(
                      email!,
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.texteSecondaire),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppButton(
          label: 'profile.account.sign_out'.tr(),
          variant: AppButtonVariant.soft,
          fullWidth: true,
          onPressed: busy ? null : () => _confirmSignOut(context, notifier),
        ),
        const SizedBox(height: 8),
        AppButton(
          label: 'profile.account.delete_account'.tr(),
          variant: AppButtonVariant.danger,
          fullWidth: true,
          onPressed: busy ? null : () => _confirmDelete(context, notifier),
        ),
        if (busy) ...[
          const SizedBox(height: 16),
          const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmSignOut(
    BuildContext context,
    AccountController notifier,
  ) async {
    final ok = await _confirmDialog(
      context,
      title: 'profile.account.sign_out_confirm_title'.tr(),
      body: 'profile.account.sign_out_confirm_body'.tr(),
      cta: 'profile.account.sign_out'.tr(),
    );
    if (ok) await notifier.signOut();
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AccountController notifier,
  ) async {
    final ok = await _confirmDialog(
      context,
      title: 'profile.account.delete_confirm_title'.tr(),
      body: 'profile.account.delete_confirm_body'.tr(),
      cta: 'profile.account.delete_account'.tr(),
    );
    if (ok) await notifier.deleteAccount();
  }

  Future<bool> _confirmDialog(
    BuildContext context, {
    required String title,
    required String body,
    required String cta,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
        ),
        title: Text(
          title,
          style: AppTypography.headingMd.copyWith(color: AppColors.error),
        ),
        content: Text(
          body,
          style: AppTypography.bodyMd.copyWith(color: AppColors.textePrimaire),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'common.cancel'.tr(),
              style: AppTypography.headingSm
                  .copyWith(color: AppColors.texteSecondaire),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              cta,
              style: AppTypography.headingSm.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}
