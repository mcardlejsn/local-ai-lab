import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('builds Material 3 light and dark themes', () {
      final lightTheme = AppTheme.light;
      final darkTheme = AppTheme.dark;

      expect(lightTheme.useMaterial3, isTrue);
      expect(lightTheme.brightness, Brightness.light);
      expect(lightTheme.colorScheme.brightness, Brightness.light);

      expect(darkTheme.useMaterial3, isTrue);
      expect(darkTheme.brightness, Brightness.dark);
      expect(darkTheme.colorScheme.brightness, Brightness.dark);
    });

    test('uses AI Blue as the shared color seed', () {
      expect(AppTheme.aiBlueSeed, const Color(0xFF4F6BED));
      expect(AppTheme.light.colorScheme.primary, isNot(Colors.transparent));
      expect(AppTheme.dark.colorScheme.primary, isNot(Colors.transparent));
    });

    test('builds selectable color and higher-contrast variants', () {
      final ThemeData teal = AppTheme.lightFor(seedColor: AppTheme.tealSeed);
      final ThemeData violet = AppTheme.darkFor(
        seedColor: AppTheme.violetSeed,
        higherContrast: true,
      );
      final ThemeData standardViolet = AppTheme.darkFor(
        seedColor: AppTheme.violetSeed,
      );

      expect(
        teal.colorScheme.primary,
        isNot(AppTheme.light.colorScheme.primary),
      );
      expect(
        violet.colorScheme.primary,
        isNot(AppTheme.dark.colorScheme.primary),
      );
      expect(violet.colorScheme, isNot(standardViolet.colorScheme));
    });

    test('provides shared shapes without overriding legacy input states', () {
      final theme = AppTheme.light;
      final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;
      final inputBorder =
          theme.inputDecorationTheme.border! as OutlineInputBorder;

      expect(
        cardShape.borderRadius,
        BorderRadius.circular(AppTheme.cardRadius),
      );
      expect(
        inputBorder.borderRadius,
        BorderRadius.circular(AppTheme.controlRadius),
      );
      expect(theme.inputDecorationTheme.filled, isNot(isTrue));
      expect(theme.inputDecorationTheme.fillColor, isNull);
      expect(theme.inputDecorationTheme.enabledBorder, isNull);
      expect(theme.inputDecorationTheme.focusedBorder, isNull);
    });
  });
}
