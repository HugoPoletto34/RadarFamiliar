import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Tipografia do Radar Familiar.
/// Títulos mais pesados, corpo mais leve — o mesmo papel do design system
/// do iLover, com a fonte padrão da plataforma.
abstract final class AppTypography {
  static TextStyle _title({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w600,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle _body({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? height,
  }) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  static TextTheme get textTheme {
    return TextTheme(
      headlineLarge: _title(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      headlineMedium: _title(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      headlineSmall: _title(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      titleLarge: _title(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      titleMedium: _title(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.primaryDark,
      ),
      bodyLarge: _body(fontSize: 16, color: AppColors.textPrimary, height: 1.4),
      bodyMedium: _body(
        fontSize: 14,
        color: AppColors.textPrimary,
        height: 1.4,
      ),
      bodySmall: _body(
        fontSize: 12,
        color: AppColors.textSecondary,
        height: 1.35,
      ),
      labelLarge: _body(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.onPrimary,
      ),
      labelMedium: _body(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
      ),
      labelSmall: _body(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }
}
