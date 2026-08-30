import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'services/app_settings_service.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const LocalAiApp());
}

class LocalAiApp extends StatefulWidget {
  const LocalAiApp({super.key, this.settingsController});

  final AppSettingsController? settingsController;

  @override
  State<LocalAiApp> createState() => _LocalAiAppState();
}

class _LocalAiAppState extends State<LocalAiApp> {
  late final AppSettingsController _settingsController;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.settingsController == null;
    _settingsController =
        widget.settingsController ?? AppSettingsController();
    if (_ownsController) unawaited(_settingsController.load());
  }

  @override
  void dispose() {
    if (_ownsController) _settingsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settingsController,
      builder: (BuildContext context, Widget? child) {
        final Color seedColor = switch (_settingsController.colorTheme) {
          AppColorTheme.aiBlue => AppTheme.aiBlueSeed,
          AppColorTheme.teal => AppTheme.tealSeed,
          AppColorTheme.violet => AppTheme.violetSeed,
        };

        return AppSettingsScope(
          controller: _settingsController,
          child: MaterialApp(
            title: 'Local AI Lab',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightFor(
              seedColor: seedColor,
              higherContrast: _settingsController.higherContrast,
            ),
            darkTheme: AppTheme.darkFor(
              seedColor: seedColor,
              higherContrast: _settingsController.higherContrast,
            ),
            themeMode: _settingsController.themeMode,
            home: const AppShell(),
          ),
        );
      },
    );
  }
}
