import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/duel_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/duel_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Crée un duel et affiche son QR code en attendant l'adversaire.
class DuelCreateView extends ConsumerStatefulWidget {
  const DuelCreateView({super.key});

  @override
  ConsumerState<DuelCreateView> createState() => _DuelCreateViewState();
}

class _DuelCreateViewState extends ConsumerState<DuelCreateView> {
  Future<({String matchId, String secret})>? _creation;

  @override
  void initState() {
    super.initState();
    _creation = ref.read(duelRepositoryProvider).createDuel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.vertForet,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, size: 22),
          color: AppColors.orSoleil,
          onPressed: () async {
            // Cleanup: supprime la session en attente.
            final res = await _creation;
            if (res != null) {
              await ref
                  .read(duelRepositoryProvider)
                  .deleteIfOwner(res.matchId);
            }
            if (!context.mounted) return;
            context.pop();
          },
        ),
        title: Text(
          "EN ATTENTE D'UN AMI",
          style: AppTypography.bebas(size: 17),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: FutureBuilder<({String matchId, String secret})>(
          future: _creation,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.orSoleil),
              );
            }
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Erreur création du duel : ${snap.error}',
                    style: AppTypography.crimson(),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final res = snap.data!;
            return _WaitingBody(matchId: res.matchId, secret: res.secret);
          },
        ),
      ),
    );
  }
}

class _WaitingBody extends ConsumerWidget {
  const _WaitingBody({required this.matchId, required this.secret});

  final String matchId;
  final String secret;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSession = ref.watch(duelSessionStreamProvider(matchId));

    // Auto-naviguer vers la game dès que le 2e joueur arrive.
    ref.listen<AsyncValue<DuelSession?>>(
      duelSessionStreamProvider(matchId),
      (prev, next) {
        final session = next.value;
        if (session == null) return;
        if (session.players.length >= 2 &&
            session.phase == DuelPhase.active) {
          context.go(AppRoutes.duelPlay, extra: session);
        }
      },
    );

    final payload = DuelSession(
      matchId: matchId,
      secret: secret,
      createdBy: '',
      createdAt: 0,
      phase: DuelPhase.waiting,
      answer: '',
      lettersPool: const [],
      riddle: '',
      explanation: '',
      proverb: '',
      players: const {},
    ).toQrPayload();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text(
            'Montre ce QR à ton ami',
            style: AppTypography.bebas(size: 18),
          ),
          const SizedBox(height: 4),
          Text(
            'Il scanne avec "Rejoindre via QR".',
            style: AppTypography.crimson(
              size: 12,
              color: AppColors.ivoire.withValues(alpha: 0.7),
              style: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.ivoire,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.orSoleil, width: 3),
            ),
            child: QrImageView(
              data: payload,
              size: 240,
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
          const SizedBox(height: 18),
          Text(
            'Code : $matchId',
            style: AppTypography.bebas(size: 22, color: AppColors.orSoleil),
          ),
          const SizedBox(height: 22),
          asyncSession.when(
            loading: () => _statusBox('Connexion...'),
            error: (_, __) => _statusBox('Erreur de connexion'),
            data: (session) {
              if (session == null) return _statusBox('Préparation...');
              final count = session.players.length;
              if (count >= 2) {
                return _statusBox('Adversaire connecté ! Démarrage...');
              }
              return _statusBox("En attente d'un adversaire...");
            },
          ),
        ],
      ),
    );
  }

  Widget _statusBox(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.bois.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.orSoleil.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.orSoleil,
              ),
            ),
            const SizedBox(width: 10),
            Text(label, style: AppTypography.bebas(size: 13)),
          ],
        ),
      );
}
