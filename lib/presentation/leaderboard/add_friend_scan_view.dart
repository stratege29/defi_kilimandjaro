import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/friends_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Parse un deep link ami : `kilimandjaro://friend/{uid}` → uid.
///
/// Retourne null si le format est invalide.
/// Exemples valides :
/// - `kilimandjaro://friend/abc123` → `'abc123'`
/// Exemples invalides (null) :
/// - `kilimandjaro://duel/...`
/// - `https://kilimandjaro.app/friend/uid`
/// - `kilimandjaro://friend/`
String? parseDeepLinkFriendUid(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (uri.scheme != 'kilimandjaro') return null;
  if (uri.host != 'friend') return null;
  final segments = uri.pathSegments;
  if (segments.isEmpty) return null;
  final uid = segments.first.trim();
  if (uid.isEmpty) return null;
  return uid;
}

/// Écran scanner QR d'un ami pour l'ajouter.
///
/// Réutilise le pattern exact de DuelScanView :
/// MobileScanner plein écran + reticle + feedback snackbar.
/// Sur scan valide → fetch profil → confirmation AlertDialog → write friendship.
class AddFriendScanView extends ConsumerStatefulWidget {
  const AddFriendScanView({super.key});

  @override
  ConsumerState<AddFriendScanView> createState() => _AddFriendScanViewState();
}

class _AddFriendScanViewState extends ConsumerState<AddFriendScanView> {
  final MobileScannerController _scanner = MobileScannerController();
  bool _processing = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    final friendUid = parseDeepLinkFriendUid(raw);
    if (friendUid == null) return;

    final myUid = _myUid;
    if (myUid == null) return;
    if (friendUid == myUid) {
      _showError('friends.error_self'.tr());
      return;
    }

    setState(() => _processing = true);
    try {
      final profile =
          await ref.read(profileRepositoryProvider).fetchProfile(friendUid);

      if (!mounted) return;
      if (profile == null) {
        _showError('friends.error_not_found'.tr());
        setState(() => _processing = false);
        return;
      }

      final confirmed = await _showConfirmation(
        displayName: profile.displayLabel,
        elo: profile.elo,
      );
      if (!mounted) return;

      if (confirmed) {
        await ref
            .read(friendsRepositoryProvider)
            .addFriend(myUid, friendUid);
        if (!mounted) return;
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
      } else {
        // Reprendre le scan si annulé.
        setState(() => _processing = false);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      _showError('error.generic'.tr());
      debugPrint('AddFriendScan error: $e');
      setState(() => _processing = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: AppTypography.bebas()),
        backgroundColor: AppColors.rouge,
      ),
    );
  }

  Future<bool> _showConfirmation({
    required String displayName,
    required int elo,
  }) async {
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          color: AppColors.orSoleil,
          onPressed: () => context.pop(),
        ),
        title: Text(
          'friends.scan_title'.tr(),
          style: AppTypography.bebas(size: 17),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scanner,
            onDetect: _onDetect,
            errorBuilder: (_, __) => const _CameraUnavailable(),
          ),
          // Reticle identique au DuelScanView.
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.orSoleil, width: 3),
              ),
            ),
          ),
          if (_processing)
            const ColoredBox(
              color: Color(0x99000000),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.orSoleil),
              ),
            ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'friends.scan_hint'.tr(),
                  style: AppTypography.bebas(size: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable();

  @override
  Widget build(BuildContext context) {
    final platform = defaultTargetPlatform;
    return Container(
      color: AppColors.vertForet,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.no_photography,
              color: AppColors.orSoleil,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'duel.camera_unavailable'.tr(),
              style: AppTypography.bebas(size: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              platform == TargetPlatform.iOS
                  ? 'duel.camera_simulator_hint'.tr()
                  : 'duel.camera_permission_hint'.tr(),
              style: AppTypography.crimson(
                size: 13,
                color: AppColors.ivoire.withValues(alpha: 0.7),
                style: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
