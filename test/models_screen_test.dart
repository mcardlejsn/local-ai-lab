import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/screens/model_download_screen.dart';
import 'package:local_ai_summarizer/services/model_manager_service.dart';
import 'package:local_ai_summarizer/theme/app_theme.dart';

void main() {
  testWidgets('Models uses Candidates, Installed, Recommended at large text', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> benchmarkChanges = ValueNotifier<int>(0);
    addTearDown(benchmarkChanges.dispose);

    await _pumpModels(
      tester,
      benchmarkChanges: benchmarkChanges,
      recommendationLoader: () async => null,
    );

    expect(find.text('Discover, manage, and compare'), findsOneWidget);
    expect(find.byKey(const Key('installed-models-summary')), findsOneWidget);
    expect(find.text('Verified'), findsNothing);
    expect(tester.takeException(), isNull);

    final Finder candidates = find.text('Candidates');
    final Finder installed = find.text('Installed');
    final Finder recommended = find.text('Recommended');
    final double candidatesX = tester.getCenter(candidates).dx;
    final double installedX = tester.getCenter(installed).dx;
    final double recommendedX = tester.getCenter(recommended).dx;
    expect(candidatesX, lessThan(installedX));
    expect(installedX, lessThan(recommendedX));
    expect(tester.getSize(candidates).height, tester.getSize(installed).height);
    expect(
      tester.getSize(recommended).height,
      tester.getSize(installed).height,
    );

    await tester.tap(candidates);
    await tester.pump();
    expect(find.byKey(const Key('candidate-test-content')), findsOneWidget);

    await tester.tap(recommended);
    await tester.pumpAndSettle();
    expect(find.text('Measured strengths'), findsOneWidget);
    expect(find.byKey(const Key('no-model-recommendations')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Recommended refreshes after the Benchmark change signal', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> benchmarkChanges = ValueNotifier<int>(0);
    addTearDown(benchmarkChanges.dispose);
    Map<String, Object?>? latest;

    await _pumpModels(
      tester,
      benchmarkChanges: benchmarkChanges,
      recommendationLoader: () async => latest,
    );

    await tester.tap(find.text('Recommended'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('no-model-recommendations')), findsOneWidget);

    latest = _recommendationSession();
    benchmarkChanges.value++;
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recommendation-evidence')), findsOneWidget);
    expect(find.text('2-Sentence Summary'), findsOneWidget);
    expect(find.text('Quality model'), findsOneWidget);
    expect(find.text('Best Recall'), findsOneWidget);
    expect(find.text('Best length compliance'), findsOneWidget);
    expect(find.text('Fast model'), findsOneWidget);
    expect(find.text('Lowest latency'), findsOneWidget);
    expect(find.text('Lowest TTFT'), findsOneWidget);
    expect(find.text('Highest generation speed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpModels(
  WidgetTester tester, {
  required ValueListenable<int> benchmarkChanges,
  required RecommendationBenchmarkLoader recommendationLoader,
}) async {
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
      home: ModelDownloadScreen(
        modelManager: ModelManagerService(),
        recommendationLoader: recommendationLoader,
        benchmarkChanges: benchmarkChanges,
        candidateBuilder: (_) => const Center(
          child: Text(
            'Candidate discovery content',
            key: Key('candidate-test-content'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, Object?> _recommendationSession() {
  return <String, Object?>{
    'id': 7,
    'completed_at': '2026-08-30T12:00:00.000Z',
    'task_type': '2-Sentence Summary',
    'runs_per_model': 3,
    'runs': <Map<String, Object?>>[
      ..._runs(
        modelOrder: 0,
        modelId: 'quality',
        modelName: 'Quality model',
        latency: 2,
        ttft: 0.4,
        tokenCount: 20,
        recall: 9,
        actualSentences: const <int>[2, 2, 2],
      ),
      ..._runs(
        modelOrder: 1,
        modelId: 'fast',
        modelName: 'Fast model',
        latency: 1,
        ttft: 0.2,
        tokenCount: 30,
        recall: 8,
        actualSentences: const <int>[2, 3, 2],
      ),
    ],
  };
}

List<Map<String, Object?>> _runs({
  required int modelOrder,
  required String modelId,
  required String modelName,
  required double latency,
  required double ttft,
  required int tokenCount,
  required int recall,
  required List<int> actualSentences,
}) {
  return List<Map<String, Object?>>.generate(3, (int index) {
    return <String, Object?>{
      'id': modelOrder * 10 + index,
      'model_order': modelOrder,
      'run_number': index + 1,
      'model_id': modelId,
      'model_name': modelName,
      'model_path': '/models/$modelId.gguf',
      'engine_type': 'gguf',
      'prompt_format': 'chatml',
      'ttft_seconds': ttft,
      'latency_seconds': latency,
      'token_count': tokenCount,
      'output_text': 'Successful output.',
      'error_message': null,
      'recall_found': recall,
      'recall_total': 10,
      'missed_fact_ids': null,
      'expected_sentence_count': 2,
      'actual_sentence_count': actualSentences[index],
    };
  });
}
