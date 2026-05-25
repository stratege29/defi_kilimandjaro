import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/data/repositories/proverb_repository.dart';
import 'package:defi_kilimandjaro/domain/entities/proverb.dart';
import 'package:defi_kilimandjaro/presentation/home/greeting.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Carte d'accueil world-class fusionnant griot, salutation et proverbe
/// du jour dans un seul bloc « accueil personnel ».
///
/// Layout : griot à gauche avec respiration idle subtile (translate Y ±2px),
/// salutation Bebas 28 orSoleil + date Crimson 12 italique à droite,
/// proverbe sur fond parchemin sous la salutation (bulle de dialogue).
/// Background container : surfaceVariant avec gradient diagonal vers
/// surfaceContainer + bordure or fine 1px.
class WelcomeCard extends ConsumerStatefulWidget {
  const WelcomeCard({super.key});

  @override
  ConsumerState<WelcomeCard> createState() => _WelcomeCardState();
}

class _WelcomeCardState extends ConsumerState<WelcomeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    // Respiration idle du griot — translate Y ±2.5px en 3.2s
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(playerProfileStreamProvider);
    final proverbAsync = ref.watch(dailyProverbProvider);
    final name = profileAsync.value?.displayName;
    final hasName = (name ?? '').trim().isNotEmpty;
    final now = DateTime.now();
    final salutation = greetingFor(now);
    final dateLabel = DateFormat('EEEE d MMMM', 'fr_FR').format(now);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surfaceVariant.withValues(alpha: 0.55),
            AppColors.surfaceContainer.withValues(alpha: 0.35),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.orSoleil.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Griot avec respiration idle.
          AnimatedBuilder(
            animation: _breath,
            builder: (_, child) {
              final offset = (_breath.value - 0.5) * 5; // ±2.5px
              return Transform.translate(
                offset: Offset(0, offset),
                child: child,
              );
            },
            child: SizedBox(
              width: 78,
              height: 110,
              child: Image.asset(AppAssets.griotWelcome),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasName ? '$salutation ${name!.trim()} !' : '$salutation !',
                  style: AppTypography.bebas(
                    size: 26,
                    color: AppColors.orSoleil,
                    letterSpacing: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _capitalize(dateLabel),
                  style: AppTypography.crimson(
                    size: 12,
                    color: AppColors.texteSecondaire,
                    style: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 10),
                _WisdomBubble(proverbAsync: proverbAsync),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Bulle parchemin avec proverbe + attribution ethnie/région.
///
/// Triangle pointant vers le griot à gauche (peint via ClipPath simple
/// container offset). Fond ivoire chaud, bordure bois.
class _WisdomBubble extends StatelessWidget {
  const _WisdomBubble({required this.proverbAsync});

  final AsyncValue<Proverb> proverbAsync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.ivoire,
            AppColors.ivoire.withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.bois.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: proverbAsync.when(
        loading: () => Text(
          '...',
          style: AppTypography.crimson(
            size: 13,
            color: AppColors.boisFonce,
            style: FontStyle.italic,
          ),
        ),
        error: (_, __) => Text(
          'La parole du jour est en chemin.',
          style: AppTypography.crimson(
            size: 13,
            color: AppColors.boisFonce,
            style: FontStyle.italic,
          ),
        ),
        data: (p) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '« ${p.text} »',
              style: AppTypography.crimson(
                size: 13,
                color: AppColors.boisFonce,
                style: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Proverbe ${p.ethnie} · ${p.region}',
              style: AppTypography.bebas(
                size: 10,
                color: AppColors.boisFonce.withValues(alpha: 0.75),
                letterSpacing: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
