import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/screens/app_shell.dart';
import 'package:local_ai_summarizer/screens/settings_screen.dart';
import 'package:local_ai_summarizer/services/app_settings_service.dart';

void main() {
  testWidgets('shell exposes four lazy state-preserving destinations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(pageBuilder: (index, _) => _ShellProbe(index: index)),
      ),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Compare'), findsOneWidget);
    expect(find.text('Models'), findsOneWidget);
    expect(find.text('Results'), findsOneWidget);
    expect(find.byKey(const Key('page-0')), findsOneWidget);
    expect(find.byKey(const Key('page-1')), findsNothing);

    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-1')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('field-1')),
      'retained benchmark state',
    );
    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();

    expect(find.text('retained benchmark state'), findsOneWidget);
  });

  testWidgets('Settings changes the persisted theme preference', (
    WidgetTester tester,
  ) async {
    final _MemorySettingsService service = _MemorySettingsService();
    final AppSettingsController controller = AppSettingsController(
      service: service,
    );
    await controller.load();

    await tester.pumpWidget(
      AppSettingsScope(
        controller: controller,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Color theme'), findsOneWidget);
    expect(find.text('AI Blue'), findsOneWidget);
    expect(find.text('Teal'), findsOneWidget);
    expect(find.text('Violet'), findsOneWidget);
    expect(find.text('Higher contrast'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(controller.themeMode, ThemeMode.dark);

    await tester.tap(find.text('Violet'));
    await tester.pumpAndSettle();
    expect(controller.colorTheme, AppColorTheme.violet);

    await tester.tap(find.byKey(const Key('higher-contrast-toggle')));
    await tester.pumpAndSettle();
    expect(controller.higherContrast, isTrue);

    expect(service.savedSettings.themeMode, ThemeMode.dark);
    expect(service.savedSettings.colorTheme, AppColorTheme.violet);
    expect(service.savedSettings.higherContrast, isTrue);

    await tester.scrollUntilVisible(find.text('About and diagnostics'), 200);
    expect(find.text('About and diagnostics'), findsOneWidget);
    expect(find.text('About Local AI Lab'), findsOneWidget);
    expect(find.text('Device and runtime information'), findsOneWidget);
    expect(find.text('Open-source licenses'), findsOneWidget);
  });

  testWidgets('Settings appearance controls support very large text', (
    WidgetTester tester,
  ) async {
    final AppSettingsController controller = AppSettingsController(
      service: _MemorySettingsService(),
    );
    await controller.load();

    await tester.pumpWidget(
      AppSettingsScope(
        controller: controller,
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2)),
            child: SettingsScreen(),
          ),
        ),
      ),
    );

    expect(find.text('System'), findsOneWidget);
    expect(find.text('AI Blue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _MemorySettingsService extends AppSettingsService {
  AppAppearanceSettings savedSettings = const AppAppearanceSettings();

  @override
  Future<AppAppearanceSettings> loadAppearanceSettings() async {
    return savedSettings;
  }

  @override
  Future<void> saveAppearanceSettings(AppAppearanceSettings settings) async {
    savedSettings = settings;
  }
}

class _ShellProbe extends StatefulWidget {
  const _ShellProbe({required this.index});

  final int index;

  @override
  State<_ShellProbe> createState() => _ShellProbeState();
}

class _ShellProbeState extends State<_ShellProbe> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: Key('page-${widget.index}'),
      body: TextField(key: Key('field-${widget.index}')),
    );
  }
}
