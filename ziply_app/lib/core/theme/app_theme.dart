import 'package:flutter/material.dart';
import 'package:ziply_app/core/theme/app_colors.dart';

/// Tema visivo dell'app. Centralizza il [ThemeData] (prima scritto inline in
/// main.dart) e lo costruisce dalla palette condivisa [AppColors].
class AppTheme {
  const AppTheme._();

  /// Tema scuro dell'app Ziply.
  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          surface: AppColors.surface,
        ),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      );
}
