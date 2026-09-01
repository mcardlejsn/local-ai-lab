import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/benchmark_test_case.dart';
import 'package:local_ai_summarizer/screens/benchmark_screen.dart';
import 'package:local_ai_summarizer/services/model_manager_service.dart';
import 'package:local_ai_summarizer/theme/app_theme.dart';
import 'package:local_ai_summarizer/widgets/benchmark_results_table.dart';

void main() {
  Future<void> pumpAtLargeText(WidgetTester tester, Widget home) async {
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
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: home,
      ),
    );
  }

  testWidgets('Benchmark exposes the approved existing-behavior structure', (
    WidgetTester tester,
  ) async {
    await pumpAtLargeText(
      tester,
      BenchmarkScreen(
        modelManager: ModelManagerService(),
        initializeOnInit: false,
      ),
    );

    expect(find.text('Compare'), findsOneWidget);
    expect(find.text('Controlled on-device comparison'), findsOneWidget);
    expect(find.byKey(const Key('benchmark-status-banner')), findsNothing);
    expect(find.byKey(const Key('benchmark-test-case-card')), findsOneWidget);
    expect(find.byKey(const Key('benchmark-model-selection')), findsOneWidget);
    expect(find.byKey(const Key('benchmark-runs-per-model')), findsOneWidget);
    expect(find.byKey(const Key('benchmark-run-button')), findsOneWidget);

    expect(find.text('From Run'), findsNothing);
    expect(find.text('Controlled test'), findsOneWidget);
    expect(find.textContaining('Length met'), findsNothing);
    expect(
      find.byKey(const Key('benchmark-read-only-instruction')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('benchmark-read-only-passage')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);

    await tester.ensureVisible(find.text('5 runs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 runs'));
    await tester.pump();
    expect(find.text('Run 0 models × 5 runs'), findsOneWidget);
  });

  testWidgets('Playground test case is a read-only reproducible snapshot', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<BenchmarkTestCase?> testCase =
        ValueNotifier<BenchmarkTestCase?>(null);
    addTearDown(testCase.dispose);

    await pumpAtLargeText(
      tester,
      BenchmarkScreen(
        modelManager: ModelManagerService(),
        initializeOnInit: false,
        playgroundTestCase: testCase,
      ),
    );

    expect(find.text('Controlled test'), findsOneWidget);

    testCase.value = const BenchmarkTestCase(
      passage: 'A Playground passage that must not drift.',
      instruction: 'Summarize this passage in exactly two sentences.',
      source: BenchmarkTestCaseSource.playground,
      taskType: '2-Sentence Summary',
    );
    await tester.pump();

    expect(find.text('From Run'), findsOneWidget);
    expect(
      find.textContaining('passage and instruction used in Run'),
      findsOneWidget,
    );
    expect(find.text('Run test case ready to compare.'), findsNothing);
    expect(
      find.text('A Playground passage that must not drift.'),
      findsOneWidget,
    );
    expect(
      find.text('Summarize this passage in exactly two sentences.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byKey(const Key('benchmark-use-controlled-test')));
    await tester.pump();

    expect(find.text('Controlled test'), findsOneWidget);
    expect(find.text('From Run'), findsNothing);
    expect(
      find.byKey(const Key('benchmark-use-playground-test')),
      findsOneWidget,
    );
    expect(find.text('Use Run test'), findsOneWidget);
    expect(find.text('Controlled test ready to compare.'), findsNothing);

    await tester.tap(find.byKey(const Key('benchmark-use-playground-test')));
    await tester.pump();

    expect(find.text('From Run'), findsOneWidget);
    expect(find.text('Controlled test'), findsNothing);
    expect(find.text('Run test case ready to compare.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('responsive result cards retain benchmark metrics and outputs', (
    WidgetTester tester,
  ) async {
    final BenchmarkAggregate nano = _aggregate(
      id: 'nano',
      name: 'Gemini Nano',
      engine: ModelEngine.nano,
      latencies: const <double>[0.68, 0.74, 0.82],
      rates: const <double>[84.2, 76.5, 71.0],
    );
    final BenchmarkAggregate gguf = _aggregate(
      id: 'qwen',
      name: 'Qwen2.5 0.5B',
      engine: ModelEngine.gguf,
      latencies: const <double>[1.00, 1.08, 1.15],
      rates: const <double>[26.0, 25.0, 24.0],
    );

    await pumpAtLargeText(
      tester,
      Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            BenchmarkResultsTable(
              aggregates: <BenchmarkAggregate>[nano, gguf],
              showAccuracy: false,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Gemini Nano'), findsOneWidget);
    expect(find.text('Qwen2.5 0.5B'), findsOneWidget);
    expect(find.text('RATE'), findsNWidgets(2));
    expect(find.text('LATENCY'), findsNWidgets(2));
    expect(find.text('EST. TOKENS'), findsNWidgets(2));
    expect(find.text('LENGTH MET'), findsNWidgets(2));
    expect(find.text('2/3'), findsNWidgets(2));
    expect(find.text('non-streaming'), findsOneWidget);
    expect(find.text('3 of 3 runs completed'), findsNWidgets(2));

    await tester.tap(find.text('View runs and output').first);
    await tester.pumpAndSettle();
    expect(find.text('Individual runs'), findsOneWidget);
    expect(find.text('Output from the median-latency run'), findsOneWidget);
    expect(find.textContaining('Run 1 ·'), findsOneWidget);
  });
}

BenchmarkAggregate _aggregate({
  required String id,
  required String name,
  required ModelEngine engine,
  required List<double> latencies,
  required List<double> rates,
}) {
  final BenchmarkAggregate aggregate = BenchmarkAggregate(
    modelId: id,
    modelName: name,
    modelPath: '/models/$id',
    engine: engine,
    promptFormat: PromptFormat.plain,
  );

  for (int index = 0; index < latencies.length; index++) {
    aggregate.runs.add(
      BenchmarkModelResult(
        modelName: name,
        engine: engine,
        ttftSeconds: engine == ModelEngine.nano ? latencies[index] : 0.31,
        totalLatencySeconds: latencies[index],
        tokenCount: 57,
        tokensPerSecond: rates[index],
        outputText: 'Representative output from $name.',
        recallFound: 8,
        recallTotal: 10,
        missedFactIds: const <String>['deadline', 'meeting'],
        expectedSentenceCount: 2,
        actualSentenceCount: index == 1 ? 3 : 2,
      ),
    );
  }

  return aggregate;
}
