import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/summary_record.dart';
import 'package:local_ai_summarizer/screens/history_screen.dart';
import 'package:local_ai_summarizer/screens/results_screen.dart';
import 'package:local_ai_summarizer/screens/saved_benchmark_sessions_screen.dart';
import 'package:local_ai_summarizer/theme/app_theme.dart';

void main() {
  testWidgets('Results keeps Run and Benchmark archives distinct', (
    WidgetTester tester,
  ) async {
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
        home: ResultsScreen(
          playgroundRunsBuilder: (_) => const Center(
            child: Text(
              'Run archive content',
              key: Key('playground-archive-test-content'),
            ),
          ),
          benchmarksBuilder: (_) => const Center(
            child: Text(
              'Benchmark archive content',
              key: Key('benchmark-archive-test-content'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Saved runs and benchmarks'), findsOneWidget);
    expect(find.text('Runs'), findsOneWidget);
    expect(find.text('Playground runs'), findsNothing);
    expect(
      find.byKey(const Key('playground-archive-test-content')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Benchmarks'));
    await tester.pump();
    expect(
      find.byKey(const Key('benchmark-archive-test-content')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved runs refresh and reveal history controls', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final ValueNotifier<int> summaryChanges = ValueNotifier<int>(0);
    addTearDown(summaryChanges.dispose);
    final List<SummaryRecord> records = <SummaryRecord>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: HistoryScreen(
              embedded: true,
              recordsLoader: () async => List<SummaryRecord>.of(records),
              summaryChanges: summaryChanges,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No saved runs yet.'), findsOneWidget);
    expect(
      find.textContaining('tap Save to keep its output and telemetry here'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('results-playground-search')), findsNothing);
    expect(
      find.byKey(const Key('results-playground-task-filter')),
      findsNothing,
    );

    records.add(
      SummaryRecord(
        id: 1,
        originalText: 'The original passage.',
        generatedSummary: 'A newly saved output.',
        taskType: '2-Sentence Summary',
        createdAt: DateTime(2026, 9, 1, 7, 15),
        latencySeconds: 1.6,
        ttftSeconds: 1.6,
        tokensPerSecond: 91.4,
        engineType: 'nano',
        modelName: 'Gemini Nano',
        tokenCount: 146,
      ),
    );
    summaryChanges.value++;
    await tester.pumpAndSettle();

    expect(find.text('A newly saved output.'), findsOneWidget);
    expect(find.text('1 saved run'), findsOneWidget);
    expect(find.byKey(const Key('results-playground-search')), findsOneWidget);
    expect(
      find.byKey(const Key('results-playground-task-filter')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Run archive controls and cards share one scroll view', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final List<SummaryRecord> records = List<SummaryRecord>.generate(
      3,
      (int index) => SummaryRecord(
        id: index + 1,
        originalText: 'Original passage $index.',
        generatedSummary: 'Saved output $index with enough text for a card.',
        taskType: '2-Sentence Summary',
        createdAt: DateTime(2026, 9, 1, 7, 15 + index),
        latencySeconds: 1.6,
        ttftSeconds: 1.6,
        tokensPerSecond: 91.4,
        engineType: 'nano',
        modelName: 'Gemini Nano',
        tokenCount: 146,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: HistoryScreen(
            embedded: true,
            recordsLoader: () async => records,
            summaryChanges: ValueNotifier<int>(0),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder archiveScroll = find.byKey(const Key('results-runs-scroll'));
    expect(archiveScroll, findsOneWidget);
    expect(
      find.descendant(
        of: archiveScroll,
        matching: find.byKey(const Key('results-playground-search')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: archiveScroll,
        matching: find.byKey(const PageStorageKey<String>('history_tile_1')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Benchmark archive is scannable at larger text', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final List<Map<String, Object?>> sessions = <Map<String, Object?>>[
      <String, Object?>{
        'id': 1,
        'completed_at': '2026-08-30T13:02:00.000',
        'model_count': 5,
        'runs_per_model': 1,
        'model_names': <String>[
          'Gemini Nano (AICore 0.release.prod_aicore_20260723)',
          'qwen2.5-1.5b-instruct-q4_k_m.gguf',
          'Falcon-H1-0.5B-Instruct-Q4_K_M.gguf',
          'qwen2.5-0.5b-instruct-q4_k_m.gguf',
          'Llama-3.2-3B-Instruct.Q4_K_M.gguf',
        ],
      },
      <String, Object?>{
        'id': 2,
        'completed_at': '2026-08-30T07:57:00.000',
        'model_count': 1,
        'runs_per_model': 1,
        'model_names': <String>['Gemini Nano'],
      },
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: SavedBenchmarkSessionsScreen(
              embedded: true,
              sessionsLoader: () async => sessions,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Finder archiveScroll = find.byKey(
      const Key('results-benchmarks-scroll'),
    );
    expect(archiveScroll, findsOneWidget);
    expect(
      find.descendant(of: archiveScroll, matching: find.text('Compare')),
      findsOneWidget,
    );
    expect(find.text('+3 more'), findsOneWidget);
    expect(find.text('Falcon-H1-0.5B-Instruct-Q4_K_M.gguf'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Delete'), findsNWidgets(2));
    expect(find.byTooltip('Delete session'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
