import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/screens/summarizer_screen.dart';
import 'package:local_ai_summarizer/services/model_manager_service.dart';
import 'package:local_ai_summarizer/theme/app_theme.dart';

void main() {
  Future<void> pumpPlayground(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: SummarizerScreen(
          modelManager: ModelManagerService(),
          scanModelsOnInit: false,
        ),
      ),
    );
  }

  testWidgets('Playground exposes the approved layout-only structure', (
    WidgetTester tester,
  ) async {
    await pumpPlayground(tester);

    expect(find.text('Playground'), findsOneWidget);
    expect(find.text('Local AI Lab · On-device'), findsOneWidget);
    expect(find.byKey(const Key('playground-model-card')), findsOneWidget);
    expect(find.byKey(const Key('playground-task-section')), findsOneWidget);
    expect(find.text('2-Sentence Summary'), findsOneWidget);
    expect(find.text('Key Events'), findsOneWidget);
    expect(find.text('Action Items'), findsOneWidget);
    expect(find.text('Custom instruction'), findsOneWidget);
    expect(find.byKey(const Key('playground-input-field')), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Sample'), findsOneWidget);
    expect(find.text('Run on device'), findsOneWidget);
    expect(find.byKey(const Key('playground-output-card')), findsOneWidget);
    expect(
      find.byKey(const Key('playground-runtime-controls')),
      findsOneWidget,
    );

    expect(find.text('Length requirement met'), findsNothing);
    expect(find.text('Use in Benchmark'), findsNothing);
  });

  testWidgets(
    'task, sample, and runtime controls retain current interactions',
    (WidgetTester tester) async {
      await pumpPlayground(tester);

      await tester.tap(find.byKey(const Key('playground-task-Custom')));
      await tester.pump();
      expect(
        find.byKey(const Key('playground-custom-instruction')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('playground-sample-button')));
      await tester.pump();
      final input = tester.widget<TextField>(
        find.byKey(const Key('playground-input-field')),
      );
      expect(input.controller!.text, contains("At Tuesday's 10:00 AM"));

      await tester.ensureVisible(find.text('Runtime controls'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Runtime controls'));
      await tester.pumpAndSettle();
      expect(find.text('Temperature'), findsOneWidget);
      expect(find.text('Top-K Sampling'), findsOneWidget);
      expect(find.text('Max Output Tokens'), findsOneWidget);
    },
  );
}
