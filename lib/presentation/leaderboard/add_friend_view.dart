import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/friends_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Écran "Ajouter un ami".
///
/// Section 1 : Mon QR code `kilimandjaro://friend/{uid}` à montrer.
/// Section 2 : Bouton pour ouvrir AddFriendScanView (camera).
/// Section 3 : Saisie manuelle de l'uid (28 chars max).
class AddFriendView extends ConsumerWidget {
  const AddFriendView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final profileAsync = ref.watch(playerProfileStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.vertForet,
      appBar: AppBar(
        backgroundColor: AppColors.vertForet,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          color: AppColors.orSoleil,
          onPressed: () => context.pop(),
          tooltip: 'common.back'.tr(),
        ),
        title: Text(
          'friends.add_title'.tr(),
          style: AppTypography.bebas(size: 18),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            _SectionHeader(title: 'friends.my_qr_title'.tr()),
            const SizedBox(height: 12),
            _MyQrCard(uid: uid, displayName: profileAsync.value?.displayLabel),
            const SizedBox(height: 28),
            _SectionHeader(title: 'friends.scan_friend_title'.tr()),
            const SizedBox(height: 12),
            _ScanFriendCard(),
            const SizedBox(height: 28),
            _SectionHeader(title: 'friends.manual_entry_title'.tr()),
            const SizedBox(height: 12),
            _ManualUidEntry(myUid: uid),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: AppTypography.bebas(size: 14));
  }
}

// ---------------------------------------------------------------------------
// Mon QR code
// ---------------------------------------------------------------------------

class _MyQrCard extends StatelessWidget {
  const _MyQrCard({required this.uid, required this.displayName});
  final String uid;
  final String? displayName;

  String get _payload => 'kilimandjaro://friend/$uid';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.orSoleil.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.ivoire,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.orSoleil, width: 2.5),
            ),
            child: QrImageView(
              data: _payload,
              size: 200,
              backgroundColor: AppColors.ivoire,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: AppColors.vertForet,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: AppColors.vertForet,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            displayName ?? 'Grimpeur anonyme',
            style: AppTypography.bebas(size: 18, color: AppColors.orSoleil),
          ),
          const SizedBox(height: 6),
          Text(
            'friends.my_qr_caption'.tr(),
            style: AppTypography.crimson(
              size: 12,
              color: AppColors.ivoire.withValues(alpha: 0.7),
              style: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scanner le QR d'un ami
// ---------------------------------------------------------------------------

class _ScanFriendCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.orSoleil.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'friends.scan_friend_body'.tr(),
            style: AppTypography.crimson(
              size: 13,
              color: AppColors.ivoire.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push(AppRoutes.addFriendScan),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.vertClair,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(
                Icons.qr_code_scanner,
                color: AppColors.ivoire,
              ),
              label: Text(
                'friends.open_camera'.tr(),
                style: AppTypography.bebas(size: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Saisie manuelle
// ---------------------------------------------------------------------------

class _ManualUidEntry extends ConsumerStatefulWidget {
  const _ManualUidEntry({required this.myUid});
  final String myUid;

  @override
  ConsumerState<_ManualUidEntry> createState() => _ManualUidEntryState();
}

class _ManualUidEntryState extends ConsumerState<_ManualUidEntry> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final uid = _controller.text.trim();
    if (uid.isEmpty) return;
    if (uid == widget.myUid) {
      setState(() => _error = 'friends.error_self'.tr());
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profile =
          await ref.read(profileRepositoryProvider).fetchProfile(uid);
      if (!mounted) return;
      if (profile == null) {
        setState(() => _error = 'friends.error_not_found'.tr());
        return;
      }

      final confirmed = await _showConfirmation(
        profile.displayLabel,
        profile.elo,
      );
      if (!mounted) return;
      if (!confirmed) return;

      await ref
          .read(friendsRepositoryProvider)
          .addFriend(widget.myUid, uid);
      if (!mounted) return;
      _controller.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'friends.add_success'.tr(args: [profile.displayLabel]),
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.vertClair,
        ),
      );
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = 'error.generic'.tr());
      debugPrint('Manual addFriend error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _showConfirmation(String displayName, int elo) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.boisFonce,
        title: Text(
          'friends.confirm_follow_title'.tr(),
          style: AppTypography.bebas(size: 18),
        ),
        content: Text(
          'friends.confirm_follow_body'.tr(args: [displayName, '$elo m']),
          style: AppTypography.crimson(size: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr(), style: AppTypography.bebas()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.vertClair,
            ),
            child: Text(
              'friends.follow_button'.tr(),
              style: AppTypography.bebas(),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bois.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.orSoleil.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'friends.manual_entry_body'.tr(),
            style: AppTypography.crimson(
              size: 12,
              color: AppColors.ivoire.withValues(alpha: 0.7),
              style: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            maxLength: 28,
            style: AppTypography.crimson(size: 13),
            decoration: InputDecoration(
              counterStyle: AppTypography.crimson(
                size: 10,
                color: AppColors.ivoire.withValues(alpha: 0.4),
              ),
              hintText: 'friends.manual_uid_hint'.tr(),
              hintStyle: AppTypography.crimson(
                size: 12,
                color: AppColors.ivoire.withValues(alpha: 0.4),
              ),
              errorText: _error,
              errorStyle: AppTypography.crimson(
                size: 11,
                color: AppColors.rouge,
              ),
              enabledBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.bois),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.orSoleil),
              ),
              errorBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.rouge),
              ),
              focusedErrorBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.rouge),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orChaud,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.ivoire,
                      ),
                    )
                  : Text(
                      'friends.add_button'.tr(),
                      style: AppTypography.bebas(size: 15),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
