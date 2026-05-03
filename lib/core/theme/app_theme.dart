import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Thème global Kilimandjaro — palette + typographies de la maquette p.2.
abstract final class AppTheme {
  static ThemeData get dark {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.orSoleil,
      onPrimary: AppColors.vertForet,
      secondary: AppColors.vertClair,
      onSecondary: AppColors.ivoire,
      tertiary: AppColors.bois,
      onTertiary: AppColors.boisFonce,
      error: AppColors.rouge,
      onError: AppColors.ivoire,
      surface: AppColors.vertForet,
      onSurface: AppColors.ivoire,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.vertForet,
      canvasColor: AppColors.vertForet,
      splashColor: AppColors.orSoleil.withValues(alpha: 0.2),
      highlightColor: AppColors.orSoleil.withValues(alpha: 0.1),
      textTheme: TextTheme(
        displayLarge: AppTypography.playfair(size: 42),
        displayMedium: AppTypography.playfair(size: 32),
        displaySmall: AppTypography.playfair(),
        headlineLarge: AppTypography.bebas(size: 32),
        headlineMedium: AppTypography.bebas(size: 24),
        headlineSmall: AppTypography.bebas(size: 18),
        titleLarge: AppTypography.bebas(size: 20),
        titleMedium: AppTypography.bebas(),
        bodyLarge: AppTypography.crimson(size: 18),
        bodyMedium: AppTypography.crimson(),
        bodySmall: AppTypography.crimson(size: 14),
        labelLarge: AppTypography.bebas(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.vertClair,
          foregroundColor: AppColors.ivoire,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: AppTypography.bebas(size: 18),
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.orSoleil),
    );
  }

  /// Status bar transparente sur tous les écrans (immersif fond vert forêt).
  static const SystemUiOverlayStyle systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.vertForet,
    systemNavigationBarIconBrightness: Brightness.light,
  );
}
