import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Scanne le QR d'un ami pour rejoindre son duel.
class DuelScanView extends ConsumerStatefulWidget {
  const DuelScanView({super.key});

  @override
  ConsumerState<DuelScanView> createState() => _DuelScanViewState();
}

class _DuelScanViewState extends ConsumerState<DuelScanView> {
  final MobileScannerController _controller = MobileScannerController();
  bool _processing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final parsed = DuelSession.parseQrPayload(raw);
    if (parsed == null) return;

    setState(() => _processing = true);
    try {
      await ref.read(duelRepositoryProvider).joinDuel(
            matchId: parsed.matchId,
            secret: parsed.secret,
          );
      // Récupère la session live pour l'envoyer à la play view.
      final session = await ref
          .read(duelRepositoryProvider)
          .watch(parsed.matchId)
          .firstWhere((s) => s != null && s.phase == DuelPhase.active);
      if (!mounted) return;
      context.go(AppRoutes.duelPlay, extra: session);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Connexion impossible : $e',
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.rouge,
        ),
      );
      setState(() => _processing = false);
    }
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
        title: Text('SCANNER LE QR', style: AppTypography.bebas(size: 17)),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (_, __) => const _CameraUnavailable(),
          ),
          // Reticle.
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.orSoleil,
                  width: 3,
                ),
              ),
            ),
          ),
          if (_processing)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.6),
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.orSoleil),
              ),
            ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Pointe ton appareil sur le QR de ton ami',
                    style: AppTypography.bebas(size: 14),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _processing ? null : _showManualCodeSheet,
                  icon: const Icon(Icons.keyboard, color: AppColors.orSoleil),
                  label: Text(
                    'SAISIR LE CODE À LA MAIN',
                    style: AppTypography.bebas(
                      size: 13,
                      color: AppColors.orSoleil,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showManualCodeSheet() async {
    final controller = TextEditingController();
    final secretCtrl = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.boisFonce,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 18,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Code du défi',
              style: AppTypography.bebas(size: 18),
            ),
            const SizedBox(height: 4),
            Text(
              'Demande à ton ami son code (6 caractères) et son secret '
              '(visible dans son URL de QR).',
              style: AppTypography.crimson(
                size: 12,
                color: AppColors.ivoire.withValues(alpha: 0.65),
                style: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: AppTypography.bebas(size: 18),
              decoration: InputDecoration(
                labelText: 'Match ID',
                labelStyle: AppTypography.crimson(size: 13),
                hintText: 'ABCD23',
                hintStyle: AppTypography.crimson(
                  size: 13,
                  color: AppColors.ivoire.withValues(alpha: 0.4),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            TextField(
              controller: secretCtrl,
              maxLength: 24,
              style: AppTypography.crimson(size: 13),
              decoration: InputDecoration(
                labelText: 'Secret (24 hex)',
                labelStyle: AppTypography.crimson(size: 13),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.vertClair,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  'REJOINDRE',
                  style: AppTypography.bebas(color: AppColors.vertForet),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final matchId = controller.text.trim().toUpperCase();
    final secret = secretCtrl.text.trim();
    if (matchId.isEmpty || secret.isEmpty) return;
    await _joinByCode(matchId, secret);
  }

  Future<void> _joinByCode(String matchId, String secret) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      await ref.read(duelRepositoryProvider).joinDuel(
            matchId: matchId,
            secret: secret,
          );
      final session = await ref
          .read(duelRepositoryProvider)
          .watch(matchId)
          .firstWhere((s) => s != null && s.phase == DuelPhase.active);
      if (!mounted) return;
      context.go(AppRoutes.duelPlay, extra: session);
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Connexion impossible : $e',
            style: AppTypography.bebas(),
          ),
          backgroundColor: AppColors.rouge,
        ),
      );
      setState(() => _processing = false);
    }
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
              'Caméra indisponible',
              style: AppTypography.bebas(size: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              platform == TargetPlatform.iOS
                  ? 'Sur simulateur iOS la caméra ne fonctionne pas. '
                      'Utilise « SAISIR LE CODE À LA MAIN » ci-dessous.'
                  : 'Vérifie que la permission caméra est accordée dans '
                      'les paramètres système.',
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
