import 'package:defi_kilimandjaro/core/constants/app_assets.dart';
import 'package:flutter/material.dart';

/// Pièce de Sagesse — sprite Sankofa or sur disque bois.
///
/// Remplace l'emoji 🪙 utilisé dans les HUD.
class CoinIcon extends StatelessWidget {
  const CoinIcon({this.size = 18, this.stack = false, super.key});

  final double size;

  /// Si `true`, affiche la pile de 3 pièces (HUD shop, gros chips).
  final bool stack;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      stack ? AppAssets.iconCoinStack : AppAssets.iconCoin,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
