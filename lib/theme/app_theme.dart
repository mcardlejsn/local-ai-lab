import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const Color aiBlueSeed = Color(0xFF4F6BED);
  static const Color tealSeed = Color(0xFF00897B);
  static const Color violetSeed = Color(0xFF7E57C2);

  static const double cardRadius = 20;
  static const double controlRadius = 16;
  static const double chipRadius = 12;

  static ThemeData get light => lightFor();

  static ThemeData get dark => darkFor();

  static ThemeData lightFor({
    Color seedColor = aiBlueSeed,
    bool higherContrast = false,
  }) => _build(
    Brightness.light,
    seedColor: seedColor,
    higherContrast: higherContrast,
  );

  static ThemeData darkFor({
    Color seedColor = aiBlueSeed,
    bool higherContrast = false,
  }) => _build(
    Brightness.dark,
    seedColor: seedColor,
    higherContrast: higherContrast,
  );

  static ThemeData _build(
    Brightness brightness, {
    required Color seedColor,
    required bool higherContrast,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      contrastLevel: higherContrast ? 1.0 : 0.0,
    );
    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
    );
    final textTheme = baseTheme.textTheme.copyWith(
      headlineSmall: baseTheme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      titleMedium: baseTheme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      labelLarge: baseTheme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(cardRadius),
    );
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(controlRadius),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );

    return baseTheme.copyWith(
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: textTheme,
      appBarTheme: AppBarThemeData(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLow,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: cardShape,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: inputBorder,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: controlShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: controlShape,
          side: BorderSide(color: colorScheme.outline),
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: baseTheme.chipTheme.copyWith(
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.secondaryContainer,
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chipRadius),
        ),
        labelStyle: textTheme.labelMedium,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.secondaryContainer,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
        ),
      ),
    );
  }
}
