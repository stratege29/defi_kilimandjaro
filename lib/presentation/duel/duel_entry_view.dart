import 'package:defi_kilimandjaro/core/router/app_router.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Point d'entrée du Défi 1v1 local. Maquette pivot Phase 6.
///
/// 2 boutons : Créer un défi ou Rejoindre via QR.
class DuelEntryView extends StatelessWidget {
  const DuelEntryView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.vertForet,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          color: AppColors.orSoleil,
          onPressed: () => context.pop(),
        ),
        title: Text('DÉFI ENTRE AMIS', style: AppTypography.bebas(size: 18)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              const Text(
                '⚔️',
                style: TextStyle(fontSize: 64),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Affronte un ami en temps réel',
                textAlign: TextAlign.center,
                style: AppTypography.bebas(size: 22),
              ),
              const SizedBox(height: 6),
              Text(
                'Le plus rapide à former le mot remporte la sagesse.',
                textAlign: TextAlign.center,
                style: AppTypography.crimson(
                  size: 14,
                  color: AppColors.ivoire.withValues(alpha: 0.75),
                  style: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 32),
              _BigButton(
                icon: Icons.qr_code_2,
                label: 'CRÉER UN DÉFI',
                description:
                    'Génère un QR code à montrer à ton ami',
                color: AppColors.vertClair,
                onTap: () => context.push(AppRoutes.duelCreate),
              ),
              const SizedBox(height: 14),
              _BigButton(
                icon: Icons.qr_code_scanner,
                label: 'REJOINDRE VIA QR',
                description: "Scanne le QR d'un ami pour rejoindre sa partie",
                color: AppColors.orSoleil,
                onTap: () => context.push(AppRoutes.duelScan),
              ),
              const SizedBox(height: 32),
              Text(
                '🌍 Internet requis pour la synchronisation temps réel.',
                textAlign: TextAlign.center,
                style: AppTypography.crimson(
                  size: 12,
                  color: AppColors.ivoire.withValues(alpha: 0.55),
                  style: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.7), width: 2),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: AppTypography.bebas(size: 18)),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: AppTypography.crimson(
                        size: 12,
                        color: AppColors.ivoire.withValues(alpha: 0.7),
                        style: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
