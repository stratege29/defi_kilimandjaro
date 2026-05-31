import 'dart:async';

import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/composite_devinette_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/composite_pack_catalog_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/pack_catalog_repository_impl.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/sync/sync_state.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:defi_kilimandjaro/domain/entities/pack_mix.dart';
import 'package:defi_kilimandjaro/presentation/my_packs/widgets/unlock_pack_dialog.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:defi_kilimandjaro/presentation/widgets/pack_icon.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Critère de tri du catalogue de packs.
enum PackSort { recent, price, alpha }

/// Écran "Mes packs" — gestion du mix de pondération + catalogue.
///
/// Entry point : icône en haut à droite de [MountainListView] (action bar),
/// la carte « Découvrir » de l'accueil, et [ProfileView].
///
/// - 1 pack possédé → vue simplifiée (pack courant + catalogue à débloquer).
/// - 2+ packs possédés → sliders de pondération + catalogue.
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

  /// Recherche texte courante sur le catalogue.
  String _query = '';

  /// Tri courant du catalogue.
  PackSort _sort = PackSort.recent;

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

    final syncState = ref.watch(manifestSyncStateProvider);
    final isSyncing = syncState is SyncStateSyncing;

    // Affiche un SnackBar éphémère à la fin de chaque sync.
    ref.listen<SyncState>(manifestSyncStateProvider, (prev, next) {
      if (prev is! SyncStateSyncing) return;
      if (next is SyncStateSuccess) {
        final String msg;
        final Color background;
        if (next.report.abortedByMemoryPressure) {
          msg = 'my_packs.sync_aborted_memory'.tr();
          background = AppColors.warningSoft;
        } else if (next.report.hasChanges) {
          msg = 'my_packs.sync_success'
              .tr(namedArgs: {'updated': '${next.report.updated}'});
          background = AppColors.boisFonce;
        } else {
          msg = 'my_packs.sync_up_to_date'.tr();
          background = AppColors.boisFonce;
        }
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: background,
              content: Text(
                msg,
                style: AppTypography.labelSm
                    .copyWith(color: AppColors.textePrimaire),
              ),
              duration: const Duration(seconds: 3),
            ),
          );
      } else if (next is SyncStateError) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: AppColors.errorSoft,
              content: Text(
                'my_packs.sync_error'.tr(),
                style: AppTypography.labelSm
                    .copyWith(color: AppColors.textePrimaire),
              ),
            ),
          );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceVariant,
        elevation: 0,
        leading: const BackButton(color: AppColors.orJour),
        title: Text('my_packs.title'.tr(), style: AppTypography.headingLg),
        actions: [
          const _CaurisBalanceChip(),
          IconButton(
            tooltip: 'my_packs.sync_button'.tr(),
            icon: const Icon(Icons.refresh, color: AppColors.orJour),
            onPressed: isSyncing
                ? null
                : () async {
                    // Phase 3 : refresh à la fois le manifest (devinettes
                    // OTA) ET le catalog distant (visibilité/ordering/prix).
                    // Les deux sont indépendants — on lance en parallèle.
                    final messenger = ScaffoldMessenger.of(context);
                    unawaited(ref
                        .read(manifestSyncStateProvider.notifier)
                        .startRefresh());
                    try {
                      await ref.read(refreshRemoteCatalogProvider.future);
                    } catch (e) {
                      // Échec catalog n'est pas bloquant — l'app continue
                      // de fonctionner sur le bundle. Juste un toast discret.
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              'Catalogue distant non récupéré ($e)',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          if (isSyncing) _SyncBanner(state: syncState),
          Expanded(
            child: asyncCatalog.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.orJour),
              ),
              error: (_, __) => Center(
                child:
                    Text('error.load_failed'.tr(), style: AppTypography.bodyMd),
              ),
              data: (catalog) {
                final owned =
                    catalog.where((p) => ownedPacks.contains(p.id)).toList();
                final notOwned =
                    catalog.where((p) => !ownedPacks.contains(p.id)).toList();
                final catalogSection = _CatalogSection(
                  notOwned: notOwned,
                  query: _query,
                  sort: _sort,
                  onQueryChanged: (q) => setState(() => _query = q),
                  onSortChanged: (s) => setState(() => _sort = s),
                );
                return owned.length >= 2
                    ? _MixView(
                        owned: owned,
                        localWeights: _localWeights ?? {},
                        onSliderChanged: _onSliderChanged,
                        catalogSection: catalogSection,
                      )
                    : _SinglePackView(
                        ownedPack: owned.isEmpty ? null : owned.first,
                        catalogSection: catalogSection,
                      );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastille de solde de cauris dans l'AppBar — miroir du header d'accueil.
/// Tap → écran de recharge (shop).
class _CaurisBalanceChip extends ConsumerWidget {
  const _CaurisBalanceChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cauris = ref.watch(playerProgressProvider).cauris;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(AppRoutes.shop),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: AppColors.orSoleil.withValues(alpha: 0.45)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CaurisIcon(size: 16),
                const SizedBox(width: 4),
                Text(
                  '$cauris',
                  style:
                      AppTypography.bebas(size: 14, color: AppColors.orSoleil),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.add_circle,
                  size: 16,
                  color: AppColors.orSoleil.withValues(alpha: 0.85),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bandeau de progression au-dessus du body pendant une sync OTA.
class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.state});

  final SyncStateSyncing state;

  @override
  Widget build(BuildContext context) {
    final packLabel = state.currentPackId ?? '…';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      color: AppColors.surfaceVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'my_packs.syncing'.tr(namedArgs: {'pack': packLabel}),
            style: AppTypography.labelSm,
          ),
          AppSpacing.gapXs,
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.progress == 0 ? null : state.progress,
              minHeight: 4,
              backgroundColor: AppColors.boisFonce,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.orJour,
              ),
            ),
          ),
        ],
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
    required this.localWeights,
    required this.onSliderChanged,
    required this.catalogSection,
  });

  final List<Pack> owned;
  final Map<String, double> localWeights;
  final void Function(String packId, double value) onSliderChanged;
  final Widget catalogSection;

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
            percent: localWeights[pack.id] ?? 0,
            onChanged: (v) => onSliderChanged(pack.id, v),
          ),
        ),
        AppSpacing.gapMd,
        _TotalIndicator(totalPercent: totalPercent, totalOk: totalOk),
        AppSpacing.gapXl,
        catalogSection,
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
    required this.catalogSection,
  });

  final Pack? ownedPack;
  final Widget catalogSection;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        AppSpacing.gapMd,
        if (ownedPack != null) ...[
          _CurrentPackTile(pack: ownedPack!),
          AppSpacing.gapXl,
        ],
        catalogSection,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Catalogue (packs à débloquer) — recherche + tri + liste
// ---------------------------------------------------------------------------

class _CatalogSection extends StatelessWidget {
  const _CatalogSection({
    required this.notOwned,
    required this.query,
    required this.sort,
    required this.onQueryChanged,
    required this.onSortChanged,
  });

  final List<Pack> notOwned;
  final String query;
  final PackSort sort;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<PackSort> onSortChanged;

  int _cost(Pack p) => p.unlockCostCauris ?? p.priceCauris;

  List<Pack> get _processed {
    final q = query.trim().toLowerCase();
    final list = q.isEmpty
        ? List<Pack>.of(notOwned)
        : notOwned.where((p) {
            final name = p.nameKey.tr().toLowerCase();
            final desc = p.descriptionKey.tr().toLowerCase();
            return name.contains(q) || desc.contains(q);
          }).toList();

    switch (sort) {
      case PackSort.recent:
        list.sort((a, b) {
          final ad = a.availableFrom;
          final bd = b.availableFrom;
          if (ad != null && bd != null) {
            final c = bd.compareTo(ad);
            if (c != 0) return c;
          } else if (ad != null) {
            return -1;
          } else if (bd != null) {
            return 1;
          }
          return a.ordering.compareTo(b.ordering);
        });
      case PackSort.price:
        list.sort((a, b) => _cost(a).compareTo(_cost(b)));
      case PackSort.alpha:
        list.sort((a, b) => a.nameKey.tr().compareTo(b.nameKey.tr()));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (notOwned.isEmpty) return const SizedBox.shrink();
    final processed = _processed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionDivider(labelKey: 'my_packs.catalog_section'),
        AppSpacing.gapMd,
        _SearchField(value: query, onChanged: onQueryChanged),
        AppSpacing.gapSm,
        _SortBar(sort: sort, onChanged: onSortChanged),
        AppSpacing.gapMd,
        if (processed.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(
              child: Text(
                'my_packs.no_results'.tr(),
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.texteTertiaire),
              ),
            ),
          )
        else
          ...processed.map((pack) => _LockedPackCard(pack: pack)),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      style: AppTypography.bodyMd.copyWith(color: AppColors.textePrimaire),
      cursorColor: AppColors.orJour,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppColors.surfaceVariant,
        hintText: 'my_packs.search_hint'.tr(),
        hintStyle:
            AppTypography.bodySm.copyWith(color: AppColors.texteTertiaire),
        prefixIcon:
            const Icon(Icons.search, color: AppColors.texteSecondaire, size: 20),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.orJour),
        ),
      ),
    );
  }
}

class _SortBar extends StatelessWidget {
  const _SortBar({required this.sort, required this.onChanged});

  final PackSort sort;
  final ValueChanged<PackSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SortChip(
          label: 'my_packs.sort_recent'.tr(),
          selected: sort == PackSort.recent,
          onTap: () => onChanged(PackSort.recent),
        ),
        const SizedBox(width: 8),
        _SortChip(
          label: 'my_packs.sort_price'.tr(),
          selected: sort == PackSort.price,
          onTap: () => onChanged(PackSort.price),
        ),
        const SizedBox(width: 8),
        _SortChip(
          label: 'my_packs.sort_alpha'.tr(),
          selected: sort == PackSort.alpha,
          onTap: () => onChanged(PackSort.alpha),
        ),
      ],
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.orJour.withValues(alpha: 0.16)
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.orJour : AppColors.hairline,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.labelSm.copyWith(
              color: selected ? AppColors.orJour : AppColors.texteSecondaire,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _PackSlider extends StatelessWidget {
  const _PackSlider({
    required this.pack,
    required this.percent,
    required this.onChanged,
  });

  final Pack pack;
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
                PackIcon(pack: pack, size: 28),
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

class _CurrentPackTile extends ConsumerWidget {
  const _CurrentPackTile({required this.pack});

  final Pack pack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Compteur "live" : bundle + cache OTA fusionnés. Fallback sur le
    // compteur bundlé du `_index.json` tant que le merge n'a pas chargé.
    final liveCount = ref
        .watch(packLiveQuestionCountProvider(pack.id))
        .maybeWhen(data: (n) => n, orElse: () => pack.questionCount);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orJour, width: 1.5),
      ),
      child: Row(
        children: [
          PackIcon(pack: pack),
          AppSpacing.hGapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pack.nameKey.tr(), style: AppTypography.headingMd),
                Text(
                  'my_packs.current_pack_label'
                      .tr(namedArgs: {'count': '$liveCount'}),
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

/// Carte d'un pack à débloquer. Toute la carte est cliquable et ouvre la
/// confirmation d'achat ([UnlockPackDialog]). Le prix est affiché avec
/// l'icône cauri. Les packs sans prix (`coming soon`) restent inertes.
class _LockedPackCard extends StatelessWidget {
  const _LockedPackCard({required this.pack});

  final Pack pack;

  /// Coût d'unlock en cauris (Phase 3 catalog + Phase 4 wallet).
  /// 0 si pack non achetable (legacy "coming soon").
  int get _unlockCost => pack.unlockCostCauris ?? pack.priceCauris;

  @override
  Widget build(BuildContext context) {
    final unlockable = _unlockCost > 0;
    final card = Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.boisFonce),
      ),
      child: Row(
        children: [
          PackIcon(pack: pack, dimmed: true),
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
                  unlockable
                      ? pack.descriptionKey.tr()
                      : 'my_packs.coming_soon'.tr(),
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.texteTertiaire,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'my_packs.question_count'
                      .tr(namedArgs: {'count': '${pack.questionCount}'}),
                  style: AppTypography.labelXs
                      .copyWith(color: AppColors.texteSecondaire),
                ),
                if (!unlockable)
                  Text(
                    'my_packs.coming_soon_sub'.tr(),
                    style: AppTypography.labelXs,
                  ),
              ],
            ),
          ),
          AppSpacing.hGapSm,
          if (unlockable)
            _PricePill(cost: _unlockCost)
          else
            const Icon(
              Icons.lock_outline,
              color: AppColors.texteDisabled,
              size: 20,
            ),
        ],
      ),
    );

    if (!unlockable) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => UnlockPackDialog.show(context, pack: pack),
        borderRadius: BorderRadius.circular(12),
        child: card,
      ),
    );
  }
}

/// Pastille de prix `coût + cauri` avec icône cauri.
class _PricePill extends StatelessWidget {
  const _PricePill({required this.cost});

  final int cost;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.orJour.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.orJour.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$cost',
            style: AppTypography.labelSm.copyWith(color: AppColors.orJour),
          ),
          const SizedBox(width: 4),
          const CaurisIcon(size: 14),
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
