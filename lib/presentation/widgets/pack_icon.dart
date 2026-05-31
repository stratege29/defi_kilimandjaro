import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/domain/entities/pack.dart';
import 'package:flutter/material.dart';

/// Icône thématique d'un pack — illustration carrée arrondie.
///
/// Remplace les emojis placebo (`🌾`, `🔥`…). Charge
/// `assets/images/packs/<id>.png` ; si l'asset n'existe pas (nouveau pack
/// remote sans visuel embarqué), retombe sur une pastille teintée par
/// `themeColorHex` avec une icône générique.
class PackIcon extends StatelessWidget {
  const PackIcon({
    required this.pack,
    this.size = 44,
    this.dimmed = false,
    super.key,
  });

  final Pack pack;
  final double size;

  /// Atténue l'icône (packs verrouillés non possédés).
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.24);
    final image = Image.asset(
      AppAssets.packIcon(pack.id),
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _fallback(),
    );
    final clipped = ClipRRect(borderRadius: radius, child: image);
    if (!dimmed) return clipped;
    return Opacity(opacity: 0.55, child: clipped);
  }

  Widget _fallback() {
    final tint = _themeColor;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(color: tint.withValues(alpha: 0.45)),
      ),
      child: Icon(Icons.style_rounded, size: size * 0.5, color: tint),
    );
  }

  Color get _themeColor {
    final hex = pack.themeColorHex;
    if (hex == null) return AppColors.orJour;
    final clean = hex.replaceAll('#', '');
    final norm = clean.length == 6 ? 'FF$clean' : clean;
    final v = int.tryParse(norm, radix: 16);
    return v == null ? AppColors.orJour : Color(v);
  }
}
