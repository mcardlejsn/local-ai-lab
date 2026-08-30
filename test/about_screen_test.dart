import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/screens/about_screen.dart';
import 'package:local_ai_summarizer/theme/app_theme.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(430, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: screen,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('About reports version, privacy, and explicit network use', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      AboutLocalAiLabScreen(
        packageDetailsLoader: () async =>
            const AppPackageDetails(version: '1.2.3', buildNumber: '45'),
      ),
    );

    expect(find.text('Version 1.2.3 (45)'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Network use'), findsOneWidget);
    expect(find.textContaining('does not use accounts'), findsOneWidget);
    expect(find.textContaining('explicitly discover'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('diagnostics reports AICore and bundled llama.cpp status', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      DeviceRuntimeScreen(
        diagnosticsLoader: () async => const RuntimeDiagnostics(
          platformDescription: 'Android 17 test device',
          geminiNanoAvailable: true,
          aiCoreVersion: '1.2.3 (456)',
        ),
      ),
    );

    expect(find.text('Android 17 test device'), findsOneWidget);
    expect(find.text('Gemini Nano · AICore'), findsOneWidget);
    expect(
      find.text('Gemini Nano available\nAICore 1.2.3 (456)'),
      findsOneWidget,
    );
    expect(find.text('GGUF · llama.cpp'), findsOneWidget);
    expect(find.textContaining('Bundled with Local AI Lab'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
