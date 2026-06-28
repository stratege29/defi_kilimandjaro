import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/pack_catalog_repository_impl.dart';
import 'package:defi_kilimandjaro/data/repositories/player_progress_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran de choix du pack gratuit initial.
///
/// Bloquant : présenté après le splash si [hasChosenFreePackProvider] == false.
/// Aucun bouton retour, pas d'accès aux autres écrans tant que le choix
/// n'est pas confirmé.
class PackChooserView extends ConsumerStatefulWidget {
  const PackChooserView({super.key});

  @override
  ConsumerState<PackChooserView> createState() => _PackChooserViewState();
}

class _PackChooserViewState extends ConsumerState<PackChooserView>
    with TickerProviderStateMixin {
  String? _selectedPackId;
  bool _confirming = false;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _selectPack(String packId) {
    if (_confirming) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedPackId = packId);
  }

  Future<void> _onConfirm(List<Pack> packs) async {
    final packId = _selectedPackId;
    if (packId == null || _confirming) return;

    final pack = packs.firstWhere((p) => p.id == packId);
    final packName =
        pack.localizedName(context.locale.languageCode) ?? pack.nameKey.tr();

    final confirmed = await _showConfirmationDialog(packName);
    if (!confirmed || !mounted) return;

    setState(() => _confirming = true);
    try {
      final notifier = ref.read(playerProgressProvider.notifier);
      // chooseFreePack possède ET active déjà le pack (activePackId). grantPack
      // est idempotent — appelé explicitement par souci de clarté du contrat.
      await notifier.chooseFreePack(packId);
      await notifier.grantPack(packId);
      if (!mounted) return;
      context.go(AppRoutes.home);
    } on Exception {
      if (!mounted) return;
      setState(() => _confirming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'error.generic'.tr(),
            style: AppTypography.bodySm,
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<bool> _showConfirmationDialog(String packName) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ConfirmDialog(packName: packName),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final asyncPacks = ref.watch(freePackCandidatesProvider);

    return PopScope(
      // Bloquant : pas de retour système possible.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: asyncPacks.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.orJour),
              ),
              error: (_, __) => Center(
                child: Text(
                  'pack_chooser.load_error'.tr(),
                  style: AppTypography.bodyMd,
                ),
              ),
              data: _buildContent,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(List<Pack> packs) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSpacing.gapLg,
          Semantics(
            header: true,
            child: Text(
              'pack_chooser.title'.tr(),
              style: AppTypography.displaySm.copyWith(
                color: AppColors.orJour,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          AppSpacing.gapSm,
          Text(
            'pack_chooser.subtitle'.tr(),
            style: AppTypography.bodySm.copyWith(color: AppColors.warning),
            textAlign: TextAlign.center,
          ),
          AppSpacing.gapXxl,
          Expanded(
            child: ListView.separated(
              itemCount: packs.length,
              separatorBuilder: (_, __) => AppSpacing.gapMd,
              itemBuilder: (_, i) => _PackCard(
                pack: packs[i],
                selected: _selectedPackId == packs[i].id,
                onTap: () => _selectPack(packs[i].id),
              ),
            ),
          ),
          AppSpacing.gapLg,
          _ConfirmButton(
            enabled: _selectedPackId != null && !_confirming,
            loading: _confirming,
            onPressed: () {
              ref.read(freePackCandidatesProvider).whenData(_onConfirm);
            },
          ),
          AppSpacing.gapSm,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pack card
// ---------------------------------------------------------------------------

class _PackCard extends StatefulWidget {
  const _PackCard({
    required this.pack,
    required this.selected,
    required this.onTap,
  });

  final Pack pack;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PackCard> createState() => _PackCardState();
}

class _PackCardState extends State<_PackCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      value: 1,
      lowerBound: 0.97,
    );
    _scaleAnim = CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    HapticFeedback.selectionClick();
    _scaleCtrl.animateTo(0.97);
  }

  void _onTapUp(TapUpDetails _) => _scaleCtrl.animateTo(1);
  void _onTapCancel() => _scaleCtrl.animateTo(1);

  /// Chemin de l'asset PNG pour le pack — fallback emoji si pack inconnu.
  /// Les PNG vivent dans `assets/images/packs/<packId>.png` (512×512).
  String? _assetFor(String packId) {
    switch (packId) {
      case 'culture_ci':
        return 'assets/images/packs/culture_ci.png';
      case 'crack_nouchi':
        return 'assets/images/packs/crack_nouchi.png';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.selected;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${widget.pack.localizedName(context.locale.languageCode) ?? widget.pack.nameKey.tr()} — ${widget.pack.localizedDescription(context.locale.languageCode) ?? widget.pack.descriptionKey.tr()}',
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (_, child) => Transform.scale(
          scale: _scaleAnim.value,
          child: child,
        ),
        child: GestureDetector(
          onTap: widget.onTap,
          onTapDown: _onTapDown,
          onTapUp: _onTapUp,
          onTapCancel: _onTapCancel,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.surfaceContainer
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? AppColors.orJour : AppColors.boisFonce,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.orJour.withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _PackIcon(assetPath: _assetFor(widget.pack.id)),
                    AppSpacing.hGapSm,
                    Expanded(
                      child: Text(
                        widget.pack.localizedName(context.locale.languageCode) ??
                            widget.pack.nameKey.tr(),
                        style: AppTypography.headingLg,
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check_circle,
                        color: AppColors.orJour,
                        size: 22,
                      ),
                  ],
                ),
                const Divider(
                  color: AppColors.boisFonce,
                  height: AppSpacing.md + AppSpacing.sm,
                ),
                Text(
                  widget.pack.localizedDescription(context.locale.languageCode) ??
                      widget.pack.descriptionKey.tr(),
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.texteSecondaire,
                  ),
                ),
                AppSpacing.gapSm,
                Row(
                  children: [
                    Text(
                      'pack_chooser.question_count'
                          .tr(namedArgs: {'count': '${widget.pack.questionCount}'}),
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.orCrepuscule,
                      ),
                    ),
                    AppSpacing.hGapSm,
                    Text(
                      '—',
                      style: AppTypography.labelSm.copyWith(
                        color: AppColors.texteSecondaire,
                      ),
                    ),
                    AppSpacing.hGapSm,
                    Expanded(
                      child: Text(
                        'pack_chooser.enriched_hint'.tr(),
                        style: AppTypography.labelXs.copyWith(
                          color: AppColors.texteTertiaire,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confirm button
// ---------------------------------------------------------------------------

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.38,
        child: GestureDetector(
          onTap: enabled ? onPressed : null,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.orJour,
              borderRadius: BorderRadius.circular(12),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: AppColors.orJour.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.surface),
                    ),
                  )
                : Text(
                    'pack_chooser.confirm_button'.tr(),
                    style: AppTypography.headingMd.copyWith(
                      color: AppColors.surface,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confirmation dialog
// ---------------------------------------------------------------------------

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.packName});

  final String packName;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'pack_chooser.dialog_title'.tr(),
        style: AppTypography.headingLg,
      ),
      content: Text(
        'pack_chooser.dialog_body'.tr(namedArgs: {'packName': packName}),
        style: AppTypography.bodyMd,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'pack_chooser.dialog_back'.tr(),
            style: AppTypography.headingSm.copyWith(
              color: AppColors.texteSecondaire,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            'pack_chooser.dialog_confirm'.tr(),
            style: AppTypography.headingSm.copyWith(color: AppColors.orJour),
          ),
        ),
      ],
    );
  }
}

/// Vignette carrée affichant l'illustration du pack (wood + ornements or).
/// Fallback sur un placeholder neutre si l'asset n'est pas livré.
class _PackIcon extends StatelessWidget {
  const _PackIcon({required this.assetPath});

  final String? assetPath;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 56,
        height: 56,
        child: assetPath == null
            ? const ColoredBox(
                color: AppColors.boisFonce,
                child: Icon(
                  Icons.layers_outlined,
                  color: AppColors.orJour,
                  size: 28,
                ),
              )
            : Image.asset(assetPath!, fit: BoxFit.cover),
      ),
    );
  }
}
