import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/composite_devinette_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/wallet/wallet_service.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:defi_kilimandjaro/presentation/widgets/app_button.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:defi_kilimandjaro/presentation/widgets/pack_icon.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Dialog de confirmation pour débloquer un pack avec ses cauris.
///
/// Carte centrée alignée sur l'overlay Victoire (Vert Nuit) : fond noir 92 %,
/// `surfaceContainer` r24, bordure hairline or, ombre noire diffuse.
///
/// Flow :
///   1. Affiche le pack (icône, nom, nb d'énigmes, description), le coût,
///      le solde courant et le solde après débit.
///   2. Bouton primaire « Débloquer » (désactivé si solde insuffisant).
///   3. Bouton « Obtenir des cauris » → boutique (recharge).
///   4. Au click Débloquer :
///      - Appelle `WalletService.unlockPack(packId)`
///      - Si `WalletException.isNotBootstrapped` → bootstrap silencieux + retry
///      - Si succès → update local (grantPack + addCauris(-cost))
///      - Sinon → affiche l'erreur typée (déjà owned, indispo, etc.)
class UnlockPackDialog extends ConsumerStatefulWidget {
  const UnlockPackDialog({required this.pack, super.key});

  final Pack pack;

  @override
  ConsumerState<UnlockPackDialog> createState() => _UnlockPackDialogState();

  /// Helper pour ouvrir le dialog. Retourne true si pack débloqué.
  static Future<bool?> show(BuildContext context, {required Pack pack}) {
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => UnlockPackDialog(pack: pack),
    );
  }
}

class _UnlockPackDialogState extends ConsumerState<UnlockPackDialog> {
  bool _processing = false;
  String? _error;

  int get _cost => widget.pack.unlockCostCauris ?? widget.pack.priceCauris;

  Future<void> _unlock() async {
    setState(() {
      _processing = true;
      _error = null;
    });

    final wallet = ref.read(walletServiceProvider);
    final progress = ref.read(playerProgressProvider.notifier);
    final localState = ref.read(playerProgressProvider);

    try {
      UnlockPackResult result;
      try {
        result = await wallet.unlockPack(packId: widget.pack.id);
      } on WalletException catch (e) {
        if (e.isNotBootstrapped) {
          // Bootstrap silencieux puis retry
          await wallet.bootstrap(
            cauris: localState.cauris,
            ownedPacks: localState.ownedPacks.toList(),
          );
          result = await wallet.unlockPack(packId: widget.pack.id);
        } else {
          rethrow;
        }
      }

      // Update local pour offline-first cohérent
      await progress.grantPack(widget.pack.id);
      await progress.addCauris(-result.cost);

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text(
            'Pack "${widget.pack.nameKey.tr()}" débloqué — '
            'solde : ${result.cauris} cauris',
          ),
        ),
      );
    } on WalletException catch (e) {
      setState(() {
        if (e.isAlreadyOwned) {
          _error = 'Tu possèdes déjà ce pack (sync en cours côté serveur).';
        } else if (e.isInsufficientFunds) {
          _error = 'Solde insuffisant côté serveur. '
              'Synchronise ton solde ou achète des cauris.';
        } else {
          _error = '${e.code} — ${e.message}';
        }
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _goToShop() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop(false);
    router.push(AppRoutes.shop);
  }

  @override
  Widget build(BuildContext context) {
    final localState = ref.watch(playerProgressProvider);
    final currentBalance = localState.cauris;
    final balanceAfter = currentBalance - _cost;
    final insufficient = balanceAfter < 0;
    final screenWidth = MediaQuery.sizeOf(context).width;

    final liveCount = ref
        .watch(packLiveQuestionCountProvider(widget.pack.id))
        .maybeWhen(data: (n) => n, orElse: () => widget.pack.questionCount);

    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: SingleChildScrollView(
          child: Container(
            width: screenWidth * 0.88,
            constraints: const BoxConstraints(maxWidth: 420),
            margin: const EdgeInsets.symmetric(vertical: 24),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.orJour.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 60,
                  offset: const Offset(0, 24),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PackIcon(pack: widget.pack, size: 72),
                const SizedBox(height: 14),
                Text(
                  widget.pack.nameKey.tr(),
                  style: AppTypography.headingLg,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                _QuestionCountChip(count: liveCount),
                const SizedBox(height: 12),
                Text(
                  widget.pack.descriptionKey.tr(),
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.texteSecondaire,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                _BalanceRow(
                  label: 'Coût',
                  value: '$_cost',
                  color: AppColors.orJour,
                ),
                const SizedBox(height: 6),
                _BalanceRow(label: 'Ton solde', value: '$currentBalance'),
                const SizedBox(height: 6),
                _BalanceRow(
                  label: 'Solde après',
                  value: insufficient ? '—' : '$balanceAfter',
                  color:
                      insufficient ? AppColors.error : AppColors.success,
                  bold: true,
                  showCauris: !insufficient,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.errorSoft.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _error!,
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.error),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                AppButton(
                  label: insufficient
                      ? 'Solde insuffisant'
                      : '${'my_packs.unlock_cta'.tr()} ($_cost)',
                  loading: _processing,
                  onPressed: insufficient ? null : _unlock,
                  fullWidth: true,
                ),
                const SizedBox(height: 10),
                AppButton(
                  label: 'my_packs.get_cauris'.tr(),
                  variant: AppButtonVariant.secondary,
                  icon: Icons.add_circle_outline,
                  onPressed: _processing ? null : _goToShop,
                  fullWidth: true,
                ),
                const SizedBox(height: 4),
                AppButton(
                  label: 'my_packs.cancel'.tr(),
                  variant: AppButtonVariant.ghost,
                  onPressed:
                      _processing ? null : () => Navigator.of(context).pop(false),
                  fullWidth: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastille « N énigmes » sous le nom du pack.
class _QuestionCountChip extends StatelessWidget {
  const _QuestionCountChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.help_outline_rounded,
            size: 14,
            color: AppColors.texteSecondaire,
          ),
          const SizedBox(width: 4),
          Text(
            'my_packs.question_count'.tr(namedArgs: {'count': '$count'}),
            style: AppTypography.labelSm
                .copyWith(color: AppColors.texteSecondaire),
          ),
        ],
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({
    required this.label,
    required this.value,
    this.color,
    this.bold = false,
    this.showCauris = true,
  });

  final String label;
  final String value;
  final Color? color;
  final bool bold;
  final bool showCauris;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style:
              AppTypography.bodySm.copyWith(color: AppColors.texteSecondaire),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: AppTypography.bodyMd.copyWith(
                color: color ?? AppColors.textePrimaire,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (showCauris) ...[
              const SizedBox(width: 4),
              const CaurisIcon(size: 14),
            ],
          ],
        ),
      ],
    );
  }
}
