import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/friends_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/player_profile.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Écran de confirmation d'ajout d'ami depuis un deep link externe.
///
/// Route : `/friend/add/:uid`
/// Déclenché par `kilimandjaro://friend/{uid}` (géré dans `redirect` du router).
///
/// Fetch le profil de [friendUid], affiche les infos et propose de suivre.
class AddFriendConfirmView extends ConsumerStatefulWidget {
  const AddFriendConfirmView({required this.friendUid, super.key});

  final String friendUid;

  @override
  ConsumerState<AddFriendConfirmView> createState() =>
      _AddFriendConfirmViewState();
}

class _AddFriendConfirmViewState
    extends ConsumerState<AddFriendConfirmView> {
  bool _submitting = false;

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    final profileAsync =
        ref.watch(_profileProvider(widget.friendUid));
    final myUid = _myUid;

    return Scaffold(
      backgroundColor: AppColors.vertForet,
      appBar: AppBar(
        backgroundColor: AppColors.vertForet,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, size: 22),
          color: AppColors.orSoleil,
          onPressed: () => context.pop(),
        ),
        title: Text(
          'friends.confirm_title'.tr(),
          style: AppTypography.bebas(size: 18),
        ),
        centerTitle: true,
      ),
      body: profileAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.orSoleil),
        ),
        error: (e, _) => _ErrorBody(message: e.toString()),
        data: (profile) {
          if (profile == null) {
            return _ErrorBody(message: 'friends.error_not_found'.tr());
          }
          if (myUid == widget.friendUid) {
            return _ErrorBody(message: 'friends.error_self'.tr());
          }

          return _ConfirmBody(
            displayName: profile.displayLabel,
            elo: profile.elo,
            submitting: _submitting,
            onFollow: () => _follow(context, myUid, profile),
          );
        },
      ),
    );
  }

  Future<void> _follow(
    BuildContext context,
    String? myUid,
    PlayerProfile profile,
  ) async {
    if (myUid == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(friendsRepositoryProvider)
          .addFriend(myUid, widget.friendUid);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'friends.add_success'.tr(args: [profile.displayLabel]),
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.vertClair,
        ),
      );
      context.pop();
    } on Exception catch (e) {
      if (!context.mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('error.generic'.tr(), style: AppTypography.bebas()),
          backgroundColor: AppColors.rouge,
        ),
      );
      debugPrint('AddFriendConfirm _follow error: $e');
    }
  }
}

/// FutureProvider.family pour le profil d'un ami (fetch ponctuel).
final _profileProvider =
    FutureProvider.family<PlayerProfile?, String>((ref, uid) {
  return ref.watch(profileRepositoryProvider).fetchProfile(uid);
});

// ---------------------------------------------------------------------------
// Body widgets
// ---------------------------------------------------------------------------

class _ConfirmBody extends StatelessWidget {
  const _ConfirmBody({
    required this.displayName,
    required this.elo,
    required this.submitting,
    required this.onFollow,
  });

  final String displayName;
  final int elo;
  final bool submitting;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grand avatar.
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.bois.withValues(alpha: 0.5),
                border: Border.all(color: AppColors.orSoleil, width: 2),
              ),
              alignment: Alignment.center,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                style: AppTypography.bebas(size: 40),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              displayName,
              style: AppTypography.playfair(size: 22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '$elo m',
              style: AppTypography.bebas(
                size: 18,
                color: AppColors.orSoleil,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'friends.confirm_follow_body'
                  .tr(args: [displayName, '$elo m']),
              style: AppTypography.crimson(
                size: 14,
                color: AppColors.ivoire.withValues(alpha: 0.8),
                style: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        submitting ? null : () => context.pop(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.bois),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'common.cancel'.tr(),
                      style: AppTypography.bebas(
                        color: AppColors.ivoire.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: submitting ? null : onFollow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.vertClair,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.ivoire,
                            ),
                          )
                        : Text(
                            'friends.follow_button'.tr(),
                            style: AppTypography.bebas(size: 15),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.rouge,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppTypography.crimson(size: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => context.pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.bois,
              ),
              child: Text(
                'common.back'.tr(),
                style: AppTypography.bebas(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
