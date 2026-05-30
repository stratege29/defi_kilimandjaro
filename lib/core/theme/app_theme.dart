import 'package:defi_kilimandjaro/core/theme/app_colors.dart';
import 'package:defi_kilimandjaro/core/theme/app_spacing.dart';
import 'package:defi_kilimandjaro/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Thème global Kilimandjaro — refonte « Vert Nuit » 2026.
///
/// Câblé sur les tokens sémantiques ([AppColors] / [AppTypography]). Toute
/// modification de peau passe par les tokens, jamais par des hex en dur ici.
abstract final class AppTheme {
  static ThemeData get dark {
    const colorScheme = ColorScheme.dark(
      // Accent primaire = or Baoulé. Texte foncé (canvas) pour le contraste.
      primary: AppColors.orJour,
      onPrimary: AppColors.surface,
      // Succès / validations.
      secondary: AppColors.success,
      onSecondary: AppColors.surface,
      // Accent chaud identitaire (Kola).
      tertiary: AppColors.kola,
      onTertiary: AppColors.textePrimaire,
      error: AppColors.error,
      onError: AppColors.textePrimaire,
      surface: AppColors.surface,
      onSurface: AppColors.textePrimaire,
      surfaceContainerHighest: AppColors.surfaceContainer,
      outline: AppColors.hairline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.surface,
      canvasColor: AppColors.surface,
      splashColor: AppColors.orJour.withValues(alpha: 0.18),
      highlightColor: AppColors.orJour.withValues(alpha: 0.10),
      textTheme: TextTheme(
        displayLarge: AppTypography.displayLg,
        displayMedium: AppTypography.displayMd,
        displaySmall: AppTypography.displaySm,
        headlineLarge: AppTypography.headingXl,
        headlineMedium: AppTypography.headingLg,
        headlineSmall: AppTypography.headingMd,
        titleLarge: AppTypography.headingLg,
        titleMedium: AppTypography.headingMd,
        titleSmall: AppTypography.headingSm,
        bodyLarge: AppTypography.bodyMd.copyWith(fontSize: 16),
        bodyMedium: AppTypography.bodyMd,
        bodySmall: AppTypography.bodySm,
        labelLarge: AppTypography.headingSm,
        labelMedium: AppTypography.labelSm,
        labelSmall: AppTypography.labelXs,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orJour,
          foregroundColor: AppColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius:
                BorderRadius.all(Radius.circular(AppSpacing.radiusMd)),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm + 2,
          ),
          textStyle: AppTypography.headingMd,
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.orJour),
    );
  }

  /// Status bar transparente + nav bar alignée sur le canvas Vert Nuit.
  static const SystemUiOverlayStyle systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  );
}
