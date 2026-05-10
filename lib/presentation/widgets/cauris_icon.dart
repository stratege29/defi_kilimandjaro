import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:flutter/material.dart';

/// Cauri de Sagesse — sprite Sankofa or sur disque bois.
///
/// Remplace l'emoji 🐚 utilisé dans les HUD.
class CaurisIcon extends StatelessWidget {
  const CaurisIcon({this.size = 18, this.stack = false, super.key});

  final double size;

  /// Si `true`, affiche la pile de 3 cauris (HUD shop, gros chips).
  final bool stack;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      stack ? AppAssets.iconCaurisStack : AppAssets.iconCauris,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
