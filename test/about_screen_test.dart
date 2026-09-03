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

  testWidgets('About explains Candidate criteria and technical terms', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      AboutLocalAiLabScreen(
        packageDetailsLoader: () async =>
            const AppPackageDetails(version: '1.2.3', buildNumber: '45'),
      ),
    );

    await tester.scrollUntilVisible(find.text('Discovery Candidates'), 400);
    expect(
      find.textContaining('mechanical download and compatibility requirements'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Curated LiteRT-LM lists exact'),
      findsOneWidget,
    );
    expect(
      find.textContaining('pinned to an immutable revision'),
      findsOneWidget,
    );
    expect(
      find.textContaining('one complete, unsharded Q4_K_M artifact'),
      findsOneWidget,
    );
    expect(find.textContaining('instruct, chat, and it-GGUF'), findsOneWidget);
    expect(
      find.textContaining('does not establish output quality'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Understanding the requirements'),
      400,
    );
    expect(find.textContaining('Q4_K_M is a balanced'), findsOneWidget);
    expect(
      find.textContaining('LiteRT-LM artifacts are packaged model files'),
      findsOneWidget,
    );
    expect(find.textContaining('Single and unsharded'), findsOneWidget);
    expect(
      find.textContaining('SHA-256 is a digital fingerprint'),
      findsOneWidget,
    );
    expect(find.textContaining('Public and ungated'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Device-specific results'), 400);
    expect(
      find.textContaining('not a runtime-memory guarantee'),
      findsOneWidget,
    );
    expect(
      find.textContaining('device-specific AICore support'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Benchmark and Recommended results are device-specific',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'results from this device do not establish a universal ranking',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('currently Android-only'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('About explains Benchmark aggregation and Recommended semantics', (
    WidgetTester tester,
  ) async {
    await pumpScreen(
      tester,
      AboutLocalAiLabScreen(
        packageDetailsLoader: () async =>
            const AppPackageDetails(version: '1.2.3', buildNumber: '45'),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('How Benchmark results are calculated'),
      400,
    );
    expect(find.textContaining('1, 3, or 5 times'), findsOneWidget);
    expect(find.textContaining('medians rather than averages'), findsOneWidget);
    expect(find.textContaining('minimum-to-maximum range'), findsOneWidget);
    expect(find.textContaining('Failed runs are excluded'), findsOneWidget);
    expect(find.textContaining('such as 4/5'), findsOneWidget);
    expect(
      find.textContaining('successful run with median latency'),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(find.text('Recommended models'), 400);
    expect(find.textContaining('most recent saved Benchmark'), findsOneWidget);
    expect(find.textContaining('at least two models'), findsOneWidget);
    expect(
      find.textContaining('only against the other models tested'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'strongest measured results for recall, length compliance when available',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'latency, time to first token (TTFT), and generation speed',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Ties are preserved'), findsOneWidget);
    expect(find.textContaining('no combined overall score'), findsOneWidget);
    expect(
      find.textContaining('comparison across multiple Benchmark sessions'),
      findsOneWidget,
    );
    expect(
      find.textContaining('device, task, models, and Benchmark comparison'),
      findsOneWidget,
    );
    expect(
      find.textContaining('guarantee of future performance'),
      findsOneWidget,
    );
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
