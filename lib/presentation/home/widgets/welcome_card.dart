import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:defi_kilimandjaro/data/repositories/profile_repository.dart';
import 'package:defi_kilimandjaro/presentation/home/greeting.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Carte d'accueil world-class : Kili animé + salutation contextuelle.
///
/// Layout : Kili à gauche avec respiration idle subtile (translate Y ±2px),
/// salutation Bebas 26 orSoleil + date Crimson 12 italique à droite.
/// Background gradient diagonal surfaceVariant → surfaceContainer avec
/// bordure or fine pour la profondeur.
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
    // Respiration idle du griot — translate Y ±2px en 3.2s
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
    final name = profileAsync.value?.displayName;
    final hasName = (name ?? '').trim().isNotEmpty;
    final now = DateTime.now();
    final salutation = greetingFor(now);
    final dateLabel = DateFormat('EEEE d MMMM', 'fr_FR').format(now);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
        children: [
          // Kili tout content (pouce levé) avec respiration idle, format compact.
          AnimatedBuilder(
            animation: _breath,
            builder: (_, child) {
              final offset = (_breath.value - 0.5) * 4; // ±2px
              return Transform.translate(
                offset: Offset(0, offset),
                child: child,
              );
            },
            child: SizedBox(
              width: 72,
              height: 53,
              child: Image.asset(AppAssets.kiliCheer, fit: BoxFit.contain),
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
                    size: 13,
                    color: AppColors.texteSecondaire,
                    style: FontStyle.italic,
                  ),
                ),
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
