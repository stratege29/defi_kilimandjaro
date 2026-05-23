import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/domain/avatars/avatar.dart';
import 'package:defi_kilimandjaro/domain/avatars/avatar_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Overlay d'introduction d'un duel — affiche les deux portraits avec
/// pseudo réel et ELO (si ranked), branché sur [playerProfileProvider].
///
/// Affichage :
/// - Portrait gauche : "Moi" + pseudo + initiale + ELO (si ranked)
/// - "VS" central
/// - Portrait droit : "Adversaire" + pseudo + initiale + ELO (si ranked)
///
/// Fallback (profil introuvable ou displayName vide) :
/// - Pseudo = "Joueur"
/// - Initiale = première lettre de l'UID
class DuelIntroOverlay extends ConsumerWidget {
  const DuelIntroOverlay({
    required this.selfUid,
    required this.opponentUid,
    required this.isRanked,
    super.key,
  });

  /// UID du joueur courant.
  final String selfUid;

  /// UID de l'adversaire — null si non encore connecté.
  final String? opponentUid;

  /// True pour un duel ranked (matchmaking ELO) : affiche le score ELO.
  final bool isRanked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: _DuelPortrait(
                  uid: selfUid,
                  label: 'Moi',
                  isSelf: true,
                  showElo: isRanked,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'VS',
                  style: AppTypography.bebas(
                    size: 32,
                    color: AppColors.orSoleil,
                  ),
                ),
              ),
              Expanded(
                child: opponentUid == null
                    ? const _WaitingPortrait()
                    : _DuelPortrait(
                        uid: opponentUid!,
                        label: 'Adversaire',
                        isSelf: false,
                        showElo: isRanked,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DuelPortrait extends ConsumerWidget {
  const _DuelPortrait({
    required this.uid,
    required this.label,
    required this.isSelf,
    required this.showElo,
  });

  final String uid;
  final String label;
  final bool isSelf;
  final bool showElo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = isSelf ? AppColors.vertClair : AppColors.orSoleil;
    final asyncProfile = ref.watch(playerProfileProvider(uid));

    return asyncProfile.when(
      loading: () => _PortraitSkeleton(label: label, color: color),
      error: (_, __) => _PortraitContent(
        label: label,
        color: color,
        pseudo: _fallbackPseudo,
        initial: _fallbackInitial(uid),
        avatar: null,
        eloLabel: null,
      ),
      data: (profile) {
        final pseudo = (profile?.displayName?.isNotEmpty ?? false)
            ? profile!.displayName!
            : _fallbackPseudo;
        final initial = (profile?.displayName?.isNotEmpty ?? false)
            ? _initialOf(profile!.displayName!)
            : _fallbackInitial(uid);
        final eloLabel = (showElo && profile != null) ? profile.altitudeLabel : null;
        final avatar = AvatarCatalog.byId(profile?.avatarId);
        return _PortraitContent(
          label: label,
          color: color,
          pseudo: pseudo,
          initial: initial,
          avatar: avatar,
          eloLabel: eloLabel,
        );
      },
    );
  }

  static const String _fallbackPseudo = 'Joueur';

  static String _fallbackInitial(String uid) =>
      uid.isEmpty ? '?' : uid.substring(0, 1).toUpperCase();

  static String _initialOf(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }
}

class _PortraitContent extends StatelessWidget {
  const _PortraitContent({
    required this.label,
    required this.color,
    required this.pseudo,
    required this.initial,
    required this.avatar,
    required this.eloLabel,
  });

  final String label;
  final Color color;
  final String pseudo;
  final String initial;
  final Avatar? avatar;
  final String? eloLabel;

  Widget _buildInitialBadge() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: AppTypography.bebas(size: 38, color: color),
      ),
    );
  }

  Widget _buildAvatarBadge(Avatar a) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: SvgPicture.asset(
        a.assetPath,
        fit: BoxFit.cover,
        placeholderBuilder: (_) => _buildInitialBadge(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = avatar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.bebas(size: 14, color: color),
        ),
        const SizedBox(height: 8),
        if (a == null) _buildInitialBadge() else _buildAvatarBadge(a),
        const SizedBox(height: 8),
        Text(
          pseudo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTypography.crimson(size: 14),
        ),
        if (eloLabel != null) ...[
          const SizedBox(height: 2),
          Text(
            eloLabel!,
            style: AppTypography.bebas(
              size: 12,
              color: AppColors.texteSecondaire,
            ),
          ),
        ],
      ],
    );
  }
}

class _PortraitSkeleton extends StatelessWidget {
  const _PortraitSkeleton({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dim = color.withValues(alpha: 0.25);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.bebas(size: 14, color: color),
        ),
        const SizedBox(height: 8),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dim,
            border: Border.all(color: dim, width: 2),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 70,
          height: 12,
          decoration: BoxDecoration(
            color: dim,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

class _WaitingPortrait extends StatelessWidget {
  const _WaitingPortrait();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'En attente...',
          style: AppTypography.bebas(
            size: 14,
            color: AppColors.texteSecondaire,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.silhouetteVerrouillee.withValues(alpha: 0.3),
            border: Border.all(
              color: AppColors.silhouetteVerrouillee,
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.person_outline,
            color: AppColors.texteTertiaire,
            size: 36,
          ),
        ),
      ],
    );
  }
}
