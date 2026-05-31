import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/wallet/wallet_service.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dialog de confirmation pour débloquer un pack avec ses cauris.
///
/// Flow :
///   1. Affiche le pack, le coût, le solde courant, le solde après débit
///   2. Si solde insuffisant → message + bouton "Acheter des cauris"
///   3. Sinon → bouton "Débloquer"
///   4. Au click :
///      - Appelle `WalletService.unlockPack(packId)`
///      - Si `WalletException.isNotBootstrapped` → bootstrap silencieux + retry
///      - Si succès → update local via `PlayerProgressRepository`
///        (grantPack + addCauris(-cost))
///      - Sinon → affiche l'erreur typée (déjà owned, indispo, etc.)
///   5. Snackbar success/error + close dialog
class UnlockPackDialog extends ConsumerStatefulWidget {
  const UnlockPackDialog({required this.pack, super.key});

  final Pack pack;

  @override
  ConsumerState<UnlockPackDialog> createState() => _UnlockPackDialogState();

  /// Helper pour ouvrir le dialog. Retourne true si pack débloqué.
  static Future<bool?> show(BuildContext context, {required Pack pack}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => UnlockPackDialog(pack: pack),
    );
  }
}

class _UnlockPackDialogState extends ConsumerState<UnlockPackDialog> {
  bool _processing = false;
  String? _error;

  int get _cost =>
      widget.pack.unlockCostCauris ?? widget.pack.priceCauris;

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
            'solde : ${result.cauris} ♦',
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

  @override
  Widget build(BuildContext context) {
    final localState = ref.watch(playerProgressProvider);
    final currentBalance = localState.cauris;
    final balanceAfter = currentBalance - _cost;
    final insufficient = balanceAfter < 0;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: _packColor(widget.pack),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.pack.nameKey.tr(),
              style: AppTypography.headingMd,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.pack.descriptionKey.tr(),
            style: AppTypography.bodySm.copyWith(color: AppColors.texteSecondaire),
          ),
          const SizedBox(height: 20),
          _BalanceRow(
            label: 'Coût',
            value: '$_cost ♦',
            color: AppColors.orJour,
          ),
          const SizedBox(height: 6),
          _BalanceRow(
            label: 'Ton solde',
            value: '$currentBalance ♦',
          ),
          const SizedBox(height: 6),
          _BalanceRow(
            label: 'Solde après',
            value: '${insufficient ? "—" : balanceAfter} ♦',
            color: insufficient ? Colors.red.shade300 : Colors.green.shade300,
            bold: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.4)),
              ),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red.shade200, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed:
              _processing ? null : () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          icon: _processing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_open, size: 16),
          label: Text(
            _processing
                ? '...'
                : insufficient
                    ? 'Solde insuffisant'
                    : 'Débloquer ($_cost ♦)',
          ),
          onPressed: (_processing || insufficient) ? null : _unlock,
        ),
      ],
    );
  }

  Color _packColor(Pack p) {
    if (p.themeColorHex == null) return AppColors.orJour;
    final hex = p.themeColorHex!.replaceAll('#', '');
    final norm = hex.length == 6 ? 'FF$hex' : hex;
    final v = int.tryParse(norm, radix: 16);
    return v == null ? AppColors.orJour : Color(v);
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({
    required this.label,
    required this.value,
    this.color,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.bodySm.copyWith(color: AppColors.texteSecondaire),
        ),
        Text(
          value,
          style: AppTypography.bodyMd.copyWith(
            color: color ?? AppColors.textePrimaire,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
