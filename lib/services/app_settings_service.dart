import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef SettingsDirectoryResolver = Future<Directory> Function();

enum AppColorTheme { aiBlue, teal, violet }

@immutable
class AppAppearanceSettings {
  const AppAppearanceSettings({
    this.themeMode = ThemeMode.system,
    this.colorTheme = AppColorTheme.aiBlue,
    this.higherContrast = false,
  });

  final ThemeMode themeMode;
  final AppColorTheme colorTheme;
  final bool higherContrast;

  AppAppearanceSettings copyWith({
    ThemeMode? themeMode,
    AppColorTheme? colorTheme,
    bool? higherContrast,
  }) {
    return AppAppearanceSettings(
      themeMode: themeMode ?? this.themeMode,
      colorTheme: colorTheme ?? this.colorTheme,
      higherContrast: higherContrast ?? this.higherContrast,
    );
  }
}

class AppSettingsService {
  AppSettingsService({SettingsDirectoryResolver? directoryResolver})
    : _directoryResolver =
          directoryResolver ?? getApplicationSupportDirectory;

  static const String _fileName = 'local_ai_lab_settings.json';
  static const String _themeModeKey = 'themeMode';
  static const String _colorThemeKey = 'colorTheme';
  static const String _higherContrastKey = 'higherContrast';

  final SettingsDirectoryResolver _directoryResolver;

  Future<AppAppearanceSettings> loadAppearanceSettings() async {
    final File file = await _settingsFile();
    if (!await file.exists()) return const AppAppearanceSettings();

    final Object? decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      return const AppAppearanceSettings();
    }
    final Object? savedHigherContrast = decoded[_higherContrastKey];

    return AppAppearanceSettings(
      themeMode: _enumValue(
        ThemeMode.values,
        decoded[_themeModeKey],
        ThemeMode.system,
      ),
      colorTheme: _enumValue(
        AppColorTheme.values,
        decoded[_colorThemeKey],
        AppColorTheme.aiBlue,
      ),
      higherContrast: savedHigherContrast is bool
          ? savedHigherContrast
          : false,
    );
  }

  Future<void> saveAppearanceSettings(AppAppearanceSettings settings) async {
    final File file = await _settingsFile();
    final File temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(<String, Object?>{
        _themeModeKey: settings.themeMode.name,
        _colorThemeKey: settings.colorTheme.name,
        _higherContrastKey: settings.higherContrast,
      }),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<ThemeMode> loadThemeMode() async {
    return (await loadAppearanceSettings()).themeMode;
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final AppAppearanceSettings current = await loadAppearanceSettings();
    await saveAppearanceSettings(current.copyWith(themeMode: mode));
  }

  T _enumValue<T extends Enum>(
    List<T> values,
    Object? saved,
    T fallback,
  ) {
    if (saved is! String) return fallback;
    for (final T value in values) {
      if (value.name == saved) return value;
    }
    return fallback;
  }

  Future<File> _settingsFile() async {
    final Directory directory = await _directoryResolver();
    if (!await directory.exists()) await directory.create(recursive: true);
    return File(p.join(directory.path, _fileName));
  }
}

class AppSettingsController extends ChangeNotifier {
  AppSettingsController({AppSettingsService? service})
    : _service = service ?? AppSettingsService();

  final AppSettingsService _service;

  AppAppearanceSettings _appearance = const AppAppearanceSettings();
  bool _isLoaded = false;
  bool _isSaving = false;
  String? _lastError;

  ThemeMode get themeMode => _appearance.themeMode;
  AppColorTheme get colorTheme => _appearance.colorTheme;
  bool get higherContrast => _appearance.higherContrast;
  bool get isLoaded => _isLoaded;
  bool get isSaving => _isSaving;
  String? get lastError => _lastError;

  Future<void> load() async {
    try {
      _appearance = await _service.loadAppearanceSettings();
      _lastError = null;
    } on Object {
      _appearance = const AppAppearanceSettings();
      _lastError = 'Could not load appearance settings.';
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (themeMode == mode && _lastError == null) return;
    await _save(_appearance.copyWith(themeMode: mode));
  }

  Future<void> setColorTheme(AppColorTheme colorTheme) async {
    if (this.colorTheme == colorTheme && _lastError == null) return;
    await _save(_appearance.copyWith(colorTheme: colorTheme));
  }

  Future<void> setHigherContrast(bool higherContrast) async {
    if (this.higherContrast == higherContrast && _lastError == null) return;
    await _save(_appearance.copyWith(higherContrast: higherContrast));
  }

  Future<void> _save(AppAppearanceSettings updated) async {
    _appearance = updated;
    _isSaving = true;
    _lastError = null;
    notifyListeners();

    try {
      await _service.saveAppearanceSettings(updated);
    } on Object {
      _lastError =
          'Appearance changed for this session but could not be saved.';
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}

class AppSettingsScope extends InheritedNotifier<AppSettingsController> {
  const AppSettingsScope({
    super.key,
    required AppSettingsController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppSettingsController of(BuildContext context) {
    final AppSettingsScope? scope = context
        .dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    assert(scope != null, 'No AppSettingsScope found in context.');
    return scope!.notifier!;
  }
}
