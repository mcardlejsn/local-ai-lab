import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/gguf_candidate_assessment.dart';
import 'package:local_ai_summarizer/models/gguf_discovery_result.dart';
import 'package:local_ai_summarizer/models/gguf_model_update.dart';
import 'package:local_ai_summarizer/screens/model_download_screen.dart';
import 'package:local_ai_summarizer/services/gguf_discovery_cache_service.dart';
import 'package:local_ai_summarizer/services/gguf_install_registry_service.dart';
import 'package:local_ai_summarizer/services/gguf_model_update_service.dart';
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
    expect(
      find.textContaining('Run Compare with at least two'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Installed shows a neutral state while the initial model scan is running',
    (WidgetTester tester) async {
      final ValueNotifier<int> benchmarkChanges = ValueNotifier<int>(0);
      addTearDown(benchmarkChanges.dispose);

      await _pumpModels(
        tester,
        benchmarkChanges: benchmarkChanges,
        recommendationLoader: () async => null,
        installedModelsOverride: const <ModelInfo>[],
        installedModelsLoadingOverride: true,
        settle: false,
      );

      expect(
        find.byKey(const Key('installed-models-scanning')),
        findsOneWidget,
      );
      expect(find.text('Scanning for models…'), findsOneWidget);
      expect(find.textContaining('0 models available'), findsNothing);
      expect(find.text('No models found'), findsNothing);
      expect(find.byKey(const Key('check-model-updates')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
    expect(find.text('Highest estimated rate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Installed checks and reviews a read-only GGUF update', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> benchmarkChanges = ValueNotifier<int>(0);
    addTearDown(benchmarkChanges.dispose);
    final GgufCandidateArtifact current = _updateArtifact(
      commitSha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      sha256Value:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      sizeBytes: 500000000,
    );
    final GgufCandidateArtifact remote = _updateArtifact(
      commitSha: 'cccccccccccccccccccccccccccccccccccccccc',
      sha256Value:
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      sizeBytes: 510000000,
    );
    final _FakeInstallRegistry registry = _FakeInstallRegistry(
      <GgufCandidateArtifact>[current],
    );
    final _FakeUpdateChecker updateChecker = _FakeUpdateChecker(
      GgufModelUpdateResult(
        status: GgufModelUpdateStatus.updateAvailable,
        installedArtifact: current,
        remoteArtifact: remote,
        message: 'The current remote artifact has a different SHA-256.',
      ),
    );

    await _pumpModels(
      tester,
      benchmarkChanges: benchmarkChanges,
      recommendationLoader: () async => null,
      installRegistry: registry,
      updateChecker: updateChecker,
      installedModelsOverride: <ModelInfo>[
        ModelInfo(
          id: '/models/${current.fileName}',
          name: current.fileName,
          path: '/models/${current.fileName}',
          engine: ModelEngine.gguf,
          sizeBytes: current.sizeBytes,
          promptFormat: PromptFormat.chatml,
        ),
      ],
    );

    expect(find.text('Qwen 1B Instruct'), findsOneWidget);
    expect(find.text('GGUF'), findsOneWidget);
    expect(find.text(current.fileName), findsNothing);

    expect(updateChecker.checkCalls, 0);
    await tester.tap(find.byKey(const Key('check-model-updates')));
    await tester.pumpAndSettle();

    expect(updateChecker.checkCalls, 1);
    expect(find.text('1 update available.'), findsOneWidget);
    expect(find.text('Update available'), findsOneWidget);

    await tester.tap(find.text('Review update'));
    await tester.pumpAndSettle();

    expect(find.text('Current installed artifact'), findsOneWidget);
    expect(find.text('Current remote artifact'), findsOneWidget);
    expect(find.text('Repository'), findsNWidgets(2));
    expect(find.text('Filename'), findsNWidgets(2));
    expect(find.text('Commit / revision'), findsNWidgets(2));
    expect(find.text('SHA-256'), findsNWidgets(2));
    expect(
      find.text('This review does not download or replace either file.'),
      findsOneWidget,
    );
    expect(find.text('Download update'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Installed adopts an exact existing cached Candidate once', (
    WidgetTester tester,
  ) async {
    final ValueNotifier<int> benchmarkChanges = ValueNotifier<int>(0);
    addTearDown(benchmarkChanges.dispose);
    final GgufCandidateArtifact artifact = _updateArtifact(
      commitSha: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      sha256Value:
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      sizeBytes: 500000000,
    );
    final _FakeInstallRegistry registry = _FakeInstallRegistry(
      <GgufCandidateArtifact>[],
    );
    final _FakeUpdateChecker updateChecker = _FakeUpdateChecker(
      GgufModelUpdateResult(
        status: GgufModelUpdateStatus.upToDate,
        installedArtifact: artifact,
        remoteArtifact: artifact,
        message: 'The installed artifact matches the current remote bytes.',
      ),
      recognitionResult: artifact,
    );
    final _FakeDiscoveryCache cache = _FakeDiscoveryCache(
      GgufDiscoveryCacheEntry(
        result: GgufDiscoveryResult(
          assessments: <GgufCandidateAssessment>[
            GgufCandidateAssessment(
              repositoryId: artifact.repositoryId,
              disposition: GgufCandidateDisposition.candidate,
              reasons: const <String>[],
              warnings: const <String>[],
              artifact: artifact,
            ),
          ],
          sourceFailures: const <GgufDiscoverySourceFailure>[],
        ),
        discoveredAtUtc: DateTime.utc(2026, 8, 30),
      ),
    );

    await _pumpModels(
      tester,
      benchmarkChanges: benchmarkChanges,
      recommendationLoader: () async => null,
      installRegistry: registry,
      discoveryCache: cache,
      updateChecker: updateChecker,
      installedModelsOverride: <ModelInfo>[
        ModelInfo(
          id: '/models/${artifact.fileName}',
          name: artifact.fileName,
          path: '/models/${artifact.fileName}',
          engine: ModelEngine.gguf,
          sizeBytes: artifact.sizeBytes,
          promptFormat: PromptFormat.chatml,
        ),
      ],
    );

    await tester.tap(find.byKey(const Key('check-model-updates')));
    await tester.pumpAndSettle();

    expect(registry.artifacts, hasLength(1));
    expect(updateChecker.recognizeCalls, 1);
    expect(updateChecker.localIdentityAlreadyVerifiedValues, <bool>[true]);
    expect(
      find.text('1 model is up to date. Recognized 1 existing exact artifact.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpModels(
  WidgetTester tester, {
  required ValueListenable<int> benchmarkChanges,
  required RecommendationBenchmarkLoader recommendationLoader,
  GgufInstallRegistry? installRegistry,
  GgufDiscoveryCache? discoveryCache,
  GgufModelUpdateChecker? updateChecker,
  List<ModelInfo>? installedModelsOverride,
  bool? installedModelsLoadingOverride,
  bool settle = true,
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
        installRegistry: installRegistry,
        discoveryCache: discoveryCache,
        updateChecker: updateChecker,
        installedModelsOverride: installedModelsOverride,
        installedModelsLoadingOverride: installedModelsLoadingOverride,
        candidateBuilder: (_) => const Center(
          child: Text(
            'Candidate discovery content',
            key: Key('candidate-test-content'),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

GgufCandidateArtifact _updateArtifact({
  required String commitSha,
  required String sha256Value,
  required int sizeBytes,
}) {
  const String repository = 'Publisher/Qwen-1B-Instruct-GGUF';
  const String fileName = 'qwen-1b-instruct-q4_k_m.gguf';
  return GgufCandidateArtifact(
    repositoryId: repository,
    commitSha: commitSha,
    fileName: fileName,
    sizeBytes: sizeBytes,
    sha256: sha256Value,
    downloadUri: Uri.parse(
      'https://huggingface.co/$repository/resolve/$commitSha/$fileName',
    ),
    sourcePage: Uri.parse('https://huggingface.co/$repository'),
    license: 'Apache-2.0',
    licenseSourceRepository: repository,
    hasCustomLicense: false,
    modelFamily: 'Qwen/ChatML',
    promptFormat: PromptFormat.chatml,
  );
}

class _FakeInstallRegistry implements GgufInstallRegistry {
  _FakeInstallRegistry(this.artifacts);

  final List<GgufCandidateArtifact> artifacts;

  @override
  Future<List<GgufCandidateArtifact>> load() async =>
      List<GgufCandidateArtifact>.unmodifiable(artifacts);

  @override
  Future<bool> record(GgufCandidateArtifact artifact) async {
    artifacts.removeWhere(
      (GgufCandidateArtifact saved) =>
          saved.fileName.toLowerCase() == artifact.fileName.toLowerCase(),
    );
    artifacts.add(artifact);
    return true;
  }

  @override
  Future<bool> remove(String fileName) async {
    artifacts.removeWhere(
      (GgufCandidateArtifact saved) =>
          saved.fileName.toLowerCase() == fileName.toLowerCase(),
    );
    return true;
  }
}

class _FakeUpdateChecker implements GgufModelUpdateChecker {
  _FakeUpdateChecker(this.result, {this.recognitionResult});

  final GgufModelUpdateResult result;
  final GgufCandidateArtifact? recognitionResult;
  int checkCalls = 0;
  int recognizeCalls = 0;
  final List<bool> localIdentityAlreadyVerifiedValues = <bool>[];

  @override
  Future<GgufModelUpdateResult> check({
    required GgufCandidateArtifact installedArtifact,
    required String installedPath,
    bool localIdentityAlreadyVerified = false,
  }) async {
    checkCalls++;
    localIdentityAlreadyVerifiedValues.add(localIdentityAlreadyVerified);
    return result;
  }

  @override
  Future<GgufCandidateArtifact?> recognizeInstalledArtifact({
    required String installedPath,
    required Iterable<GgufCandidateArtifact> candidates,
  }) async {
    recognizeCalls++;
    return recognitionResult;
  }
}

class _FakeDiscoveryCache implements GgufDiscoveryCache {
  _FakeDiscoveryCache(this.entry);

  GgufDiscoveryCacheEntry? entry;

  @override
  Future<GgufDiscoveryCacheEntry?> load() async => entry;

  @override
  Future<bool> save(
    GgufDiscoveryResult result, {
    required DateTime discoveredAtUtc,
  }) async {
    entry = GgufDiscoveryCacheEntry(
      result: result,
      discoveredAtUtc: discoveredAtUtc,
    );
    return true;
  }
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
