import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
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
            child: Center(
              child: Container(
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
            ),
          ),
        ],
      ),
    );
  }
}
