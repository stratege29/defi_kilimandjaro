import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/domain/avatars/avatar.dart';
import 'package:defi_kilimandjaro/domain/avatars/avatar_catalog.dart';
import 'package:defi_kilimandjaro/domain/entities/player_profile.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

/// Écran de sélection d'avatar.
///
/// Architecture :
/// - Lit le profil courant via `playerProfileStreamProvider` (ELO + avatarId
///   actuel).
/// - Maintient une `_selectedId` locale (preview) jusqu'à validation.
/// - Affiche le catalogue groupé par [AvatarCategory], avec état verrouillé
///   pour les avatars dont `unlockMinElo` n'est pas atteint.
/// - "Valider" appelle `ProfileRepository.updateAvatar` puis `context.pop()`.
///
/// **Skeleton** : pas encore branché dans le routeur — ouverture future depuis
/// `profile_view.dart` (tap sur `_AvatarBadge`).
class AvatarPickerView extends ConsumerStatefulWidget {
  const AvatarPickerView({super.key});

  @override
  ConsumerState<AvatarPickerView> createState() => _AvatarPickerViewState();
}

class _AvatarPickerViewState extends ConsumerState<AvatarPickerView> {
  /// Sélection en cours (preview locale, non persistée tant que `Valider`
  /// n'est pas pressé). Null = on garde l'avatar actuel.
  String? _selectedId;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final asyncProfile = ref.watch(playerProfileStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.vertForet,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'profile.avatar_picker.title'.tr(),
          style: AppTypography.bebas(size: 18),
        ),
        iconTheme: const IconThemeData(color: AppColors.orSoleil),
      ),
      body: asyncProfile.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.orSoleil),
        ),
        error: (e, _) => Center(
          child: Text(
            'error.generic'.tr(),
            style: AppTypography.crimson(),
          ),
        ),
        data: (profile) => _buildBody(context, profile),
      ),
    );
  }

  Widget _buildBody(BuildContext context, PlayerProfile profile) {
    final grouped = AvatarCatalog.groupedByCategory();
    final currentId = _selectedId ?? profile.avatarId;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            children: [
              for (final entry in grouped.entries) ...[
                _CategoryHeader(category: entry.key),
                const SizedBox(height: 8),
                _AvatarGrid(
                  avatars: entry.value,
                  selectedId: currentId,
                  playerElo: profile.elo,
                  onTap: _onTapAvatar,
                ),
                const SizedBox(height: 18),
              ],
            ],
          ),
        ),
        _BottomBar(
          canSave: _selectedId != null && _selectedId != profile.avatarId,
          saving: _saving,
          onSave: () => _save(profile.uid),
        ),
      ],
    );
  }

  void _onTapAvatar(Avatar avatar, {required bool isUnlocked}) {
    if (!isUnlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            'profile.avatar_picker.locked_snackbar'.tr(
              namedArgs: {'elo': '${avatar.unlockMinElo}'},
            ),
          ),
        ),
      );
      return;
    }
    setState(() => _selectedId = avatar.id);
  }

  Future<void> _save(String uid) async {
    final id = _selectedId;
    if (id == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).updateAvatar(uid, id);
      if (!mounted) return;
      context.pop();
    } on Exception {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('error.generic'.tr())),
      );
    }
  }
}

// =============================================================================
// Sub-widgets
// =============================================================================

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.category});

  final AvatarCategory category;

  String get _labelKey {
    switch (category) {
      case AvatarCategory.griot:
        return 'profile.avatar_picker.category.griot';
      case AvatarCategory.masque:
        return 'profile.avatar_picker.category.masque';
      case AvatarCategory.vieQuotidienne:
        return 'profile.avatar_picker.category.vie_quotidienne';
      case AvatarCategory.aliment:
        return 'profile.avatar_picker.category.aliment';
      case AvatarCategory.instrument:
        return 'profile.avatar_picker.category.instrument';
      case AvatarCategory.faune:
        return 'profile.avatar_picker.category.faune';
      case AvatarCategory.wildcard:
        return 'profile.avatar_picker.category.wildcard';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          _labelKey.tr(),
          style: AppTypography.bebas(color: AppColors.orSoleil),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Divider(
            color: AppColors.orSoleil.withValues(alpha: 0.25),
            thickness: 1,
          ),
        ),
      ],
    );
  }
}

class _AvatarGrid extends StatelessWidget {
  const _AvatarGrid({
    required this.avatars,
    required this.selectedId,
    required this.playerElo,
    required this.onTap,
  });

  final List<Avatar> avatars;
  final String? selectedId;
  final int playerElo;
  final void Function(Avatar avatar, {required bool isUnlocked}) onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: avatars.length,
      itemBuilder: (context, i) {
        final avatar = avatars[i];
        final unlocked = avatar.isUnlockedFor(playerElo);
        final selected = avatar.id == selectedId;
        return _AvatarTile(
          avatar: avatar,
          isUnlocked: unlocked,
          isSelected: selected,
          onTap: () => onTap(avatar, isUnlocked: unlocked),
        );
      },
    );
  }
}

class _AvatarTile extends StatelessWidget {
  const _AvatarTile({
    required this.avatar,
    required this.isUnlocked,
    required this.isSelected,
    required this.onTap,
  });

  final Avatar avatar;
  final bool isUnlocked;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isSelected ? AppColors.orSoleil : Colors.white.withValues(alpha: 0.08);
    final borderWidth = isSelected ? 2.5 : 1.0;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.bois.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: isSelected
              ? <BoxShadow>[
                  BoxShadow(
                    color: AppColors.orSoleil.withValues(alpha: 0.35),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: ColorFiltered(
                  colorFilter: isUnlocked
                      ? const ColorFilter.mode(
                          Colors.transparent,
                          BlendMode.dst,
                        )
                      : const ColorFilter.matrix(<double>[
                          0.2126, 0.7152, 0.0722, 0, 0, //
                          0.2126, 0.7152, 0.0722, 0, 0, //
                          0.2126, 0.7152, 0.0722, 0, 0, //
                          0, 0, 0, 1, 0, //
                        ]),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SvgPicture.asset(
                        avatar.assetPath,
                        placeholderBuilder: (_) => _AvatarPlaceholder(
                          id: avatar.id,
                        ),
                      ),
                      if (!isUnlocked)
                        const Icon(
                          Icons.lock,
                          color: AppColors.orSoleil,
                          size: 28,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              avatar.nameKey.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypography.bebas(
                size: 11,
                color: isUnlocked
                    ? AppColors.textePrimaire
                    : AppColors.texteTertiaire,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.boisFonce.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        id.isNotEmpty ? id[0].toUpperCase() : '?',
        style: AppTypography.bebas(size: 28, color: AppColors.orSoleil),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.canSave,
    required this.saving,
    required this.onSave,
  });

  final bool canSave;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: (canSave && !saving) ? onSave : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.orSoleil,
              foregroundColor: AppColors.vertForet,
              disabledBackgroundColor:
                  AppColors.orSoleil.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.vertForet,
                    ),
                  )
                : Text(
                    'profile.avatar_picker.validate'.tr(),
                    style: AppTypography.bebas(),
                  ),
          ),
        ),
      ),
    );
  }
}
