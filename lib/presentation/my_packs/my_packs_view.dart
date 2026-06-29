import 'dart:async';

import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/composite_devinette_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/composite_pack_catalog_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/pack_catalog_repository_impl.dart';
import 'package:defi_kilimandjaro/data/repositories/pack_notification_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/data/sync/sync_state.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:defi_kilimandjaro/presentation/hub/widgets/bottom_nav_bar.dart';
import 'package:defi_kilimandjaro/presentation/my_packs/widgets/pack_updates_banner.dart';
import 'package:defi_kilimandjaro/presentation/my_packs/widgets/unlock_pack_dialog.dart';
import 'package:defi_kilimandjaro/presentation/packs/pack_display.dart';
import 'package:defi_kilimandjaro/presentation/widgets/cauris_icon.dart';
import 'package:defi_kilimandjaro/presentation/widgets/pack_icon.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Critère de tri du catalogue de packs.
enum PackSort { recent, price, alpha }

/// Écran "Mes packs" — sélection du pack actif + catalogue à débloquer.
///
/// Entry point : chip pack actif (header carte montagnes + accueil), la carte
/// « Découvrir » de l'accueil, et l'écran Profil.
///
/// Modèle « pack actif unique » : la liste des packs possédés permet d'activer
/// celui qu'on veut gravir (chaque pack a sa propre progression de montagnes).
/// Le catalogue liste les packs à débloquer.
class MyPacksView extends ConsumerStatefulWidget {
  const MyPacksView({super.key});

  @override
  ConsumerState<MyPacksView> createState() => _MyPacksViewState();
}

class _MyPacksViewState extends ConsumerState<MyPacksView> {
  /// Recherche texte courante sur le catalogue.
  String _query = '';

  /// Tri courant du catalogue.
  PackSort _sort = PackSort.recent;

  /// Déclenche la synchro OTA (devinettes) + le refresh du catalogue distant.
  /// Partagé entre le bouton de l'AppBar et le bandeau de mises à jour.
  /// Seul point qui lance un download — toujours sur action utilisateur.
  Future<void> _triggerSync() async {
    if (ref.read(manifestSyncStateProvider) is SyncStateSyncing) return;
    final messenger = ScaffoldMessenger.of(context);
    unawaited(ref.read(manifestSyncStateProvider.notifier).startRefresh());
    try {
      await ref.read(refreshRemoteCatalogProvider.future);
    } on Object catch (e) {
      // Échec catalog n'est pas bloquant — l'app continue de fonctionner sur
      // le bundle. Juste un toast discret.
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Catalogue distant non récupéré ($e)'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncCatalog = ref.watch(packCatalogProvider);
    final ownedPacks = ref.watch(ownedPacksProvider);

    final syncState = ref.watch(manifestSyncStateProvider);
    final isSyncing = syncState is SyncStateSyncing;

    // Packs possédés ayant une MAJ de contenu disponible (réseau borné).
    final updatablePacks = ref.watch(packUpdatesProvider).maybeWhen(
          data: (ids) => ids,
          orElse: () => const <String>[],
        );
    final hasUpdates = updatablePacks.isNotEmpty;

    // Messenger capturé au build (élément actif) : ne JAMAIS appeler
    // `ScaffoldMessenger.of(context)` dans le callback de `ref.listen`. Une
    // fin de sync qui arrive pendant le pop de l'écran ferait un lookup
    // d'inherited widget sur un élément en cours de désactivation →
    // assertion `_dependents.isEmpty` et écran d'erreur global.
    final messenger = ScaffoldMessenger.of(context);

    // Affiche un SnackBar éphémère à la fin de chaque sync.
    ref.listen<SyncState>(manifestSyncStateProvider, (prev, next) {
      if (!mounted) return;
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
        // Recalcule le bandeau « MAJ dispo » après une sync réussie.
        ref.invalidate(packUpdatesProvider);
        messenger
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
        messenger
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
            icon: hasUpdates && !isSyncing
                ? Badge(
                    backgroundColor: AppColors.orJour,
                    label: Text(
                      '${updatablePacks.length}',
                      style: AppTypography.labelXs
                          .copyWith(color: AppColors.boisFonce),
                    ),
                    child: const Icon(Icons.refresh, color: AppColors.orJour),
                  )
                : const Icon(Icons.refresh, color: AppColors.orJour),
            // Phase 3 : refresh manifest OTA + catalog distant (cf _triggerSync).
            onPressed: isSyncing ? null : _triggerSync,
          ),
        ],
      ),
      body: Column(
        children: [
          if (isSyncing) _SyncBanner(state: syncState),
          if (!isSyncing && hasUpdates)
            PackUpdatesBanner(
              count: updatablePacks.length,
              onUpdate: _triggerSync,
            ),
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
                return _OwnedPacksView(
                  owned: owned,
                  catalogSection: catalogSection,
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        current: NavTab.packs,
        onTabSelected: (t) {
          switch (t) {
            case NavTab.accueil:
              context.go(AppRoutes.home);
            case NavTab.defi:
              context.go(AppRoutes.hub);
            case NavTab.sommets:
              context.go(AppRoutes.mountains);
            case NavTab.packs:
              break;
            case NavTab.profil:
              context.go(AppRoutes.profile);
          }
        },
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
// Owned packs view — sélection du pack ACTIF (modèle « pack actif unique »)
// ---------------------------------------------------------------------------

class _OwnedPacksView extends StatelessWidget {
  const _OwnedPacksView({
    required this.owned,
    required this.catalogSection,
  });

  final List<Pack> owned;
  final Widget catalogSection;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        AppSpacing.gapMd,
        if (owned.isNotEmpty) ...[
          Text('my_packs.active_title'.tr(), style: AppTypography.headingXl),
          AppSpacing.gapXs,
          Text('my_packs.active_subtitle'.tr(), style: AppTypography.bodySm),
          AppSpacing.gapLg,
          ...owned.map((pack) => _OwnedPackTile(pack: pack)),
          AppSpacing.gapXl,
        ],
        catalogSection,
      ],
    );
  }
}

/// Tuile d'un pack possédé. Tap → active ce pack (`setActivePack`) **et**
/// saute directement dans son ascension (`/mountains`) pour jouer sans
/// détour. Le pack actif est mis en avant (bordure or + check).
class _OwnedPackTile extends ConsumerWidget {
  const _OwnedPackTile({required this.pack});

  final Pack pack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = ref.watch(activePackIdProvider) == pack.id;
    // Compteur "live" : bundle + cache OTA fusionnés. Fallback sur le
    // compteur bundlé du `_index.json` tant que le merge n'a pas chargé.
    final liveCount = ref
        .watch(packLiveQuestionCountProvider(pack.id))
        .maybeWhen(data: (n) => n, orElse: () => pack.questionCount);

    Future<void> play() async {
      if (!isActive) {
        // `pack` provient de la liste des packs possédés → setActivePack ne
        // lèvera pas (il valide l'appartenance).
        await ref.read(playerProgressProvider.notifier).setActivePack(pack.id);
      }
      if (!context.mounted) return;
      // Saut direct dans l'ascension du pack actif — supprime l'aller-retour
      // (ressortir vers l'accueil puis revenir) pointé par les retours joueurs.
      context.go(AppRoutes.mountains);
    }

    final tile = Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? AppColors.orJour : AppColors.hairline,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          PackIcon(pack: pack),
          AppSpacing.hGapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pack.displayName, style: AppTypography.headingMd),
                Text(
                  'my_packs.current_pack_label'
                      .tr(namedArgs: {'count': '$liveCount'}),
                  style: AppTypography.bodySm,
                ),
              ],
            ),
          ),
          AppSpacing.hGapSm,
          if (isActive) ...[
            const Icon(Icons.check_circle, color: AppColors.orJour, size: 20),
            AppSpacing.hGapXs,
          ],
          const _PlayPill(),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: play,
        borderRadius: BorderRadius.circular(12),
        child: tile,
      ),
    );
  }
}

/// Pastille d'action « Jouer » (flèche play + label or) sur une tuile de
/// pack possédé. Lance directement l'ascension du pack.
class _PlayPill extends StatelessWidget {
  const _PlayPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.orJour.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.orJour.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.play_arrow_rounded,
            size: 16,
            color: AppColors.orJour,
          ),
          const SizedBox(width: 4),
          Text(
            'my_packs.play'.tr(),
            style: AppTypography.bebas(size: 13, color: AppColors.orJour),
          ),
        ],
      ),
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
            final name = p.displayName.toLowerCase();
            final desc = p.displayDescription.toLowerCase();
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
        list.sort((a, b) => a.displayName.compareTo(b.displayName));
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
                  pack.displayName,
                  style: AppTypography.headingSm.copyWith(
                    color: AppColors.texteSecondaire,
                  ),
                ),
                Text(
                  unlockable
                      ? pack.displayDescription
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
