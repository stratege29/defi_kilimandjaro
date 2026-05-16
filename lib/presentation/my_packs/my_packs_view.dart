import 'dart:async';

import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/pack_catalog_repository_impl.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Écran "Mes packs" — gestion du mix de pondération + vue catalogue.
///
/// Entry point : icône en haut à droite de [MountainListView] (action bar)
/// et depuis [ProfileView] (section Paramètres).
///
/// - 1 pack possédé → vue simplifiée (pack courant + section "débloquer").
/// - 2+ packs possédés → sliders de pondération avec rebalance automatique.
class MyPacksView extends ConsumerStatefulWidget {
  const MyPacksView({super.key});

  @override
  ConsumerState<MyPacksView> createState() => _MyPacksViewState();
}

class _MyPacksViewState extends ConsumerState<MyPacksView> {
  /// Poids locaux en cours d'édition (0–100, somme = 100).
  /// Initialisés depuis [activePackMix] lors du premier build.
  Map<String, double>? _localWeights;

  /// Timer de debounce pour éviter spam I/O sur chaque pixel de drag.
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Réajuste les poids des autres packs lorsque [changedId] bouge vers
  /// [newValue] (en pourcentages). Algorithme proportionnel :
  /// l'excédent est redistribué proportionnellement aux poids actuels des
  /// autres packs. Si tous les autres sont à 0, on répartit équitablement.
  ///
  /// Garanties :
  /// - Somme des valeurs retournées == 100.
  /// - Aucune valeur < 0.
  Map<String, double> _rebalance(
    Map<String, double> current,
    String changedId,
    double newValue,
  ) {
    final clamped = newValue.clamp(0.0, 100.0);
    final others = Map<String, double>.from(current)..remove(changedId);

    if (others.isEmpty) {
      return {changedId: 100};
    }

    final remainder = (100 - clamped).clamp(0.0, 100.0);
    final othersSum = others.values.fold<double>(0, (a, b) => a + b);

    Map<String, double> newOthers;
    if (othersSum <= 0) {
      // All others are at 0 — distribute evenly.
      final share = remainder / others.length;
      newOthers = others.map((k, _) => MapEntry(k, share));
    } else {
      // Proportional redistribution.
      newOthers = others.map(
        (k, v) => MapEntry(k, (v / othersSum) * remainder),
      );
    }

    return {changedId: clamped, ...newOthers};
  }

  void _onSliderChanged(String packId, double value) {
    final current = _localWeights;
    if (current == null) return;
    final rebalanced = _rebalance(current, packId, value);
    setState(() => _localWeights = rebalanced);

    // Debounce the repository call (300 ms).
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _persistMix(rebalanced);
    });
  }

  Future<void> _persistMix(Map<String, double> percentWeights) async {
    // Strip entries at 0 and convert to 0–1 weights.
    final positive = <String, double>{
      for (final entry in percentWeights.entries)
        if (entry.value > 0) entry.key: entry.value / 100,
    };
    if (positive.isEmpty) return;

    try {
      final mix = PackMix.normalized(positive);
      await ref.read(playerProgressProvider.notifier).setPackMix(mix);
    } on Exception {
      // Owned-pack validation failure — defensive, UI pre-validates.
    }
  }

  String _emojiFor(String packId) {
    switch (packId) {
      case 'culture_ci':
        return '\u{1F33E}';
      case 'crack_nouchi':
        return '\u{1F525}';
      default:
        return '\u{1F4DA}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncCatalog = ref.watch(packCatalogProvider);
    final ownedPacks = ref.watch(ownedPacksProvider);
    final activeMix = ref.watch(packMixProvider);

    // Initialise local weights once from the persisted mix, adding zeros for
    // owned packs not yet in the mix (unlikely but defensive).
    if (_localWeights == null && ownedPacks.isNotEmpty) {
      final initial = <String, double>{};
      for (final id in ownedPacks) {
        final weight = activeMix.weights[id] ?? 0;
        initial[id] = weight * 100;
      }
      // Normalise to 100 in case of rounding.
      final sum = initial.values.fold<double>(0, (a, b) => a + b);
      if (sum > 0) {
        _localWeights = initial.map((k, v) => MapEntry(k, v / sum * 100));
      } else if (ownedPacks.isNotEmpty) {
        final share = 100.0 / ownedPacks.length;
        _localWeights = {for (final id in ownedPacks) id: share};
      }
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceVariant,
        elevation: 0,
        leading: const BackButton(color: AppColors.orJour),
        title: Text('my_packs.title'.tr(), style: AppTypography.headingLg),
      ),
      body: asyncCatalog.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.orJour),
        ),
        error: (_, __) => Center(
          child: Text('error.load_failed'.tr(), style: AppTypography.bodyMd),
        ),
        data: (catalog) {
          final owned = catalog.where((p) => ownedPacks.contains(p.id)).toList();
          final notOwned =
              catalog.where((p) => !ownedPacks.contains(p.id)).toList();
          return owned.length >= 2
              ? _MixView(
                  owned: owned,
                  notOwned: notOwned,
                  localWeights: _localWeights ?? {},
                  emojiFor: _emojiFor,
                  onSliderChanged: _onSliderChanged,
                )
              : _SinglePackView(
                  ownedPack: owned.isEmpty ? null : owned.first,
                  notOwned: notOwned,
                  emojiFor: _emojiFor,
                );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Multi-pack mix view (2+ packs owned)
// ---------------------------------------------------------------------------

class _MixView extends StatelessWidget {
  const _MixView({
    required this.owned,
    required this.notOwned,
    required this.localWeights,
    required this.emojiFor,
    required this.onSliderChanged,
  });

  final List<Pack> owned;
  final List<Pack> notOwned;
  final Map<String, double> localWeights;
  final String Function(String) emojiFor;
  final void Function(String packId, double value) onSliderChanged;

  @override
  Widget build(BuildContext context) {
    final totalPercent =
        localWeights.values.fold<double>(0, (a, b) => a + b).round();
    final totalOk = (totalPercent - 100).abs() <= 1;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        AppSpacing.gapMd,
        Text('my_packs.mix_title'.tr(), style: AppTypography.headingXl),
        AppSpacing.gapXs,
        Text(
          'my_packs.mix_subtitle'.tr(),
          style: AppTypography.bodySm,
        ),
        AppSpacing.gapLg,
        ...owned.map(
          (pack) => _PackSlider(
            pack: pack,
            emoji: emojiFor(pack.id),
            percent: localWeights[pack.id] ?? 0,
            onChanged: (v) => onSliderChanged(pack.id, v),
          ),
        ),
        AppSpacing.gapMd,
        _TotalIndicator(totalPercent: totalPercent, totalOk: totalOk),
        if (notOwned.isNotEmpty) ...[
          AppSpacing.gapXl,
          const _SectionDivider(labelKey: 'my_packs.available_section'),
          AppSpacing.gapMd,
          ...notOwned.map((pack) => _LockedPackCard(pack: pack, emoji: emojiFor(pack.id))),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Single-pack view (1 pack owned)
// ---------------------------------------------------------------------------

class _SinglePackView extends StatelessWidget {
  const _SinglePackView({
    required this.ownedPack,
    required this.notOwned,
    required this.emojiFor,
  });

  final Pack? ownedPack;
  final List<Pack> notOwned;
  final String Function(String) emojiFor;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        AppSpacing.gapMd,
        if (ownedPack != null) ...[
          _CurrentPackTile(
            pack: ownedPack!,
            emoji: emojiFor(ownedPack!.id),
          ),
          AppSpacing.gapXl,
        ],
        if (notOwned.isNotEmpty) ...[
          const _SectionDivider(labelKey: 'my_packs.unlock_section'),
          AppSpacing.gapMd,
          ...notOwned.map(
            (pack) => _LockedPackCard(pack: pack, emoji: emojiFor(pack.id)),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _PackSlider extends StatelessWidget {
  const _PackSlider({
    required this.pack,
    required this.emoji,
    required this.percent,
    required this.onChanged,
  });

  final Pack pack;
  final String emoji;
  final double percent;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final displayPct = percent.round();
    return Semantics(
      label: '${pack.nameKey.tr()} — $displayPct%',
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(
                    pack.nameKey.tr(),
                    style: AppTypography.headingSm,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: Text(
                    '$displayPct%',
                    key: ValueKey(displayPct),
                    style: AppTypography.headingMd.copyWith(
                      color: AppColors.orJour,
                    ),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.orJour,
                inactiveTrackColor: AppColors.boisFonce,
                thumbColor: AppColors.orCrepuscule,
                overlayColor: AppColors.orJour.withValues(alpha: 0.12),
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              ),
              child: Slider(
                value: percent.clamp(0.0, 100.0),
                max: 100,
                divisions: 100,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalIndicator extends StatelessWidget {
  const _TotalIndicator({
    required this.totalPercent,
    required this.totalOk,
  });

  final int totalPercent;
  final bool totalOk;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: totalOk ? AppColors.successSoft : AppColors.warningSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            totalOk ? Icons.check_circle_outline : Icons.warning_amber_outlined,
            color: totalOk ? AppColors.success : AppColors.warning,
            size: 18,
          ),
          AppSpacing.hGapSm,
          Text(
            totalOk
                ? 'my_packs.total_ok'.tr()
                : 'my_packs.total_label'
                    .tr(namedArgs: {'total': '$totalPercent'}),
            style: AppTypography.labelSm.copyWith(
              color: totalOk ? AppColors.success : AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentPackTile extends StatelessWidget {
  const _CurrentPackTile({required this.pack, required this.emoji});

  final Pack pack;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orJour, width: 1.5),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          AppSpacing.hGapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pack.nameKey.tr(), style: AppTypography.headingMd),
                Text(
                  'my_packs.current_pack_label'
                      .tr(namedArgs: {'count': '${pack.questionCount}'}),
                  style: AppTypography.bodySm,
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: AppColors.orJour, size: 20),
        ],
      ),
    );
  }
}

class _LockedPackCard extends StatelessWidget {
  const _LockedPackCard({required this.pack, required this.emoji});

  final Pack pack;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.boisFonce),
      ),
      child: Row(
        children: [
          Text(
            emoji,
            style: const TextStyle(
              fontSize: 28,
              color: AppColors.texteDisabled,
            ),
          ),
          AppSpacing.hGapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pack.nameKey.tr(),
                  style: AppTypography.headingSm.copyWith(
                    color: AppColors.texteSecondaire,
                  ),
                ),
                Text(
                  'my_packs.coming_soon'.tr(),
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.texteTertiaire,
                  ),
                ),
                Text(
                  'my_packs.coming_soon_sub'.tr(),
                  style: AppTypography.labelXs,
                ),
              ],
            ),
          ),
          const Icon(Icons.lock_outline, color: AppColors.texteDisabled, size: 20),
        ],
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.labelKey});

  final String labelKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.boisFonce)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            labelKey.tr(),
            style: AppTypography.labelSm.copyWith(
              color: AppColors.texteSecondaire,
            ),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.boisFonce)),
      ],
    );
  }
}
