import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/services/app_settings_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late AppSettingsService service;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'local-ai-lab-settings-',
    );
    service = AppSettingsService(directoryResolver: () async => directory);
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('appearance settings default and survive reload', () async {
    final AppAppearanceSettings defaults = await service
        .loadAppearanceSettings();
    expect(defaults.themeMode, ThemeMode.system);
    expect(defaults.colorTheme, AppColorTheme.aiBlue);
    expect(defaults.higherContrast, isFalse);

    const AppAppearanceSettings saved = AppAppearanceSettings(
      themeMode: ThemeMode.dark,
      colorTheme: AppColorTheme.violet,
      higherContrast: true,
    );
    await service.saveAppearanceSettings(saved);

    final AppAppearanceSettings restored = await service
        .loadAppearanceSettings();
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.colorTheme, AppColorTheme.violet);
    expect(restored.higherContrast, isTrue);
  });

  test('existing theme-only settings receive new defaults', () async {
    final File settingsFile = File(
      p.join(directory.path, 'local_ai_lab_settings.json'),
    );
    await settingsFile.writeAsString(
      jsonEncode(<String, Object?>{'themeMode': 'light'}),
    );

    final AppAppearanceSettings restored = await service
        .loadAppearanceSettings();
    expect(restored.themeMode, ThemeMode.light);
    expect(restored.colorTheme, AppColorTheme.aiBlue);
    expect(restored.higherContrast, isFalse);
  });

  test('controller restores and saves every appearance preference', () async {
    await service.saveAppearanceSettings(
      const AppAppearanceSettings(
        themeMode: ThemeMode.dark,
        colorTheme: AppColorTheme.teal,
        higherContrast: true,
      ),
    );
    final AppSettingsController controller = AppSettingsController(
      service: service,
    );

    await controller.load();
    expect(controller.isLoaded, isTrue);
    expect(controller.themeMode, ThemeMode.dark);
    expect(controller.colorTheme, AppColorTheme.teal);
    expect(controller.higherContrast, isTrue);

    await controller.setThemeMode(ThemeMode.system);
    await controller.setColorTheme(AppColorTheme.violet);
    await controller.setHigherContrast(false);

    final AppAppearanceSettings restored = await service
        .loadAppearanceSettings();
    expect(restored.themeMode, ThemeMode.system);
    expect(restored.colorTheme, AppColorTheme.violet);
    expect(restored.higherContrast, isFalse);
  });
}
