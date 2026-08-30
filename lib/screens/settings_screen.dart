import 'package:flutter/material.dart';

import '../services/app_settings_service.dart';
import '../theme/app_theme.dart';
import 'about_screen.dart';

Future<void> openSettings(BuildContext context) async {
  await Navigator.of(
    context,
  ).push<void>(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final AppSettingsController controller = AppSettingsScope.of(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                'Appearance',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Theme', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 12),
                          _ChoiceGroup<ThemeMode>(
                            selectedValue: controller.themeMode,
                            enabled: !controller.isSaving,
                            choices: const <_AppearanceChoice<ThemeMode>>[
                              _AppearanceChoice<ThemeMode>(
                                value: ThemeMode.system,
                                label: 'System',
                              ),
                              _AppearanceChoice<ThemeMode>(
                                value: ThemeMode.light,
                                label: 'Light',
                              ),
                              _AppearanceChoice<ThemeMode>(
                                value: ThemeMode.dark,
                                label: 'Dark',
                              ),
                            ],
                            onSelected: (ThemeMode mode) => _saveSetting(
                              context,
                              controller.setThemeMode(mode),
                              controller,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Color theme',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          _ChoiceGroup<AppColorTheme>(
                            selectedValue: controller.colorTheme,
                            enabled: !controller.isSaving,
                            choices: const <_AppearanceChoice<AppColorTheme>>[
                              _AppearanceChoice<AppColorTheme>(
                                value: AppColorTheme.aiBlue,
                                label: 'AI Blue',
                                swatch: AppTheme.aiBlueSeed,
                              ),
                              _AppearanceChoice<AppColorTheme>(
                                value: AppColorTheme.teal,
                                label: 'Teal',
                                swatch: AppTheme.tealSeed,
                              ),
                              _AppearanceChoice<AppColorTheme>(
                                value: AppColorTheme.violet,
                                label: 'Violet',
                                swatch: AppTheme.violetSeed,
                              ),
                            ],
                            onSelected: (AppColorTheme colorTheme) =>
                                _saveSetting(
                                  context,
                                  controller.setColorTheme(colorTheme),
                                  controller,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Divider(color: colors.outlineVariant),
                    SwitchListTile(
                      key: const Key('higher-contrast-toggle'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      secondary: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colors.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.contrast_outlined,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                      title: const Text('Higher contrast'),
                      subtitle: const Text(
                        'Increase separation between text and surfaces',
                      ),
                      value: controller.higherContrast,
                      onChanged: controller.isSaving
                          ? null
                          : (bool value) => _saveSetting(
                              context,
                              controller.setHigherContrast(value),
                              controller,
                            ),
                    ),
                    if (controller.isSaving)
                      const LinearProgressIndicator(minHeight: 2),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'About and diagnostics',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  side: BorderSide(color: colors.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: <Widget>[
                    _SettingsActionTile(
                      key: const Key('about-local-ai-lab'),
                      icon: Icons.info_outline_rounded,
                      title: 'About Local AI Lab',
                      subtitle: 'Version, privacy, and network-use information',
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const AboutLocalAiLabScreen(),
                        ),
                      ),
                    ),
                    Divider(height: 1, color: colors.outlineVariant),
                    _SettingsActionTile(
                      key: const Key('device-runtime-information'),
                      icon: Icons.monitor_heart_outlined,
                      title: 'Device and runtime information',
                      subtitle: 'AICore and llama.cpp status',
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const DeviceRuntimeScreen(),
                        ),
                      ),
                    ),
                    Divider(height: 1, color: colors.outlineVariant),
                    _SettingsActionTile(
                      key: const Key('open-source-licenses'),
                      icon: Icons.receipt_long_outlined,
                      title: 'Open-source licenses',
                      onTap: () => openOpenSourceLicenses(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveSetting(
    BuildContext context,
    Future<void> operation,
    AppSettingsController controller,
  ) async {
    await operation;
    if (!context.mounted || controller.lastError == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(controller.lastError!)));
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: colors.onPrimaryContainer),
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _ChoiceGroup<T> extends StatelessWidget {
  const _ChoiceGroup({
    required this.selectedValue,
    required this.enabled,
    required this.choices,
    required this.onSelected,
  });

  final T selectedValue;
  final bool enabled;
  final List<_AppearanceChoice<T>> choices;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final double textScale = MediaQuery.textScalerOf(context).scale(1);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool stackChoices =
            textScale >= 1.8 || constraints.maxWidth < 300;
        if (stackChoices) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _withSpacing(
              choices.map(_buildChoice).toList(growable: false),
            ),
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _withSpacing(
              choices
                  .map(
                    (_AppearanceChoice<T> choice) =>
                        Expanded(child: _buildChoice(choice)),
                  )
                  .toList(growable: false),
              horizontal: true,
            ),
          ),
        );
      },
    );
  }

  Widget _buildChoice(_AppearanceChoice<T> choice) {
    return _AppearanceChoiceButton<T>(
      choice: choice,
      selected: choice.value == selectedValue,
      enabled: enabled,
      onPressed: () => onSelected(choice.value),
    );
  }

  List<Widget> _withSpacing(List<Widget> children, {bool horizontal = false}) {
    return <Widget>[
      for (int index = 0; index < children.length; index++) ...<Widget>[
        if (index > 0)
          SizedBox(width: horizontal ? 10 : 0, height: horizontal ? 0 : 10),
        children[index],
      ],
    ];
  }
}

class _AppearanceChoice<T> {
  const _AppearanceChoice({
    required this.value,
    required this.label,
    this.swatch,
  });

  final T value;
  final String label;
  final Color? swatch;
}

class _AppearanceChoiceButton<T> extends StatelessWidget {
  const _AppearanceChoiceButton({
    required this.choice,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final _AppearanceChoice<T> choice;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Color foreground = selected
        ? colors.onPrimaryContainer
        : colors.onSurface;
    final bool placeSwatchAboveLabel =
        choice.swatch != null &&
        MediaQuery.textScalerOf(context).scale(1) > 1.1;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        constraints: const BoxConstraints(minHeight: 64),
        decoration: BoxDecoration(
          color: selected
              ? colors.primaryContainer
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTheme.controlRadius),
          border: Border.all(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppTheme.controlRadius),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: placeSwatchAboveLabel
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: choice.swatch,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          choice.label,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: foreground,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (choice.swatch case final Color swatch) ...<Widget>[
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: swatch,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            choice.label,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: foreground,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
