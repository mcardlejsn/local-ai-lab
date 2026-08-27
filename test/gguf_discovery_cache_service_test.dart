import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/gguf_candidate_assessment.dart';
import 'package:local_ai_summarizer/models/gguf_compatibility_policy.dart';
import 'package:local_ai_summarizer/models/gguf_discovery_result.dart';
import 'package:local_ai_summarizer/services/gguf_discovery_cache_service.dart';

void main() {
  late Directory temporaryDirectory;
  late GgufDiscoveryCacheService cache;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'local_ai_lab_gguf_discovery_cache_',
    );
    cache = GgufDiscoveryCacheService(
      directoryProvider: () async => temporaryDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('round-trips only downloadable Candidates and diagnostics', () async {
    final DateTime discoveredAtUtc = DateTime.utc(2026, 8, 27, 5, 2);
    final GgufDiscoveryResult result = GgufDiscoveryResult(
      assessments: <GgufCandidateAssessment>[
        _candidate(),
        const GgufCandidateAssessment(
          repositoryId: 'Publisher/Needs-Review-GGUF',
          disposition: GgufCandidateDisposition.needsReview,
          reasons: <String>['Manual review required.'],
          warnings: <String>[],
        ),
      ],
      sourceFailures: const <GgufDiscoverySourceFailure>[
        GgufDiscoverySourceFailure(
          repositoryId: 'Publisher/Unavailable-GGUF',
          message: 'Repository metadata unavailable.',
        ),
      ],
    );

    expect(
      await cache.save(result, discoveredAtUtc: discoveredAtUtc),
      isTrue,
    );

    final GgufDiscoveryCacheEntry? restored = await cache.load();
    expect(restored, isNotNull);
    final GgufDiscoveryCacheEntry entry = restored!;
    expect(entry.discoveredAtUtc, discoveredAtUtc);
    expect(entry.result.assessments, hasLength(1));
    expect(
      entry.result.assessments.single.repositoryId,
      'Qwen/Qwen2.5-3B-Instruct-GGUF',
    );
    expect(entry.result.assessments.single.canDownload, isTrue);
    expect(
      entry.result.assessments.single.artifact!.promptFormat,
      PromptFormat.chatml,
    );
    expect(
      entry.result.assessments.single.warnings,
      <String>['Review qwen-research terms before download.'],
    );
    expect(entry.result.sourceFailures, hasLength(1));
  });

  test('a newer successful result replaces the previous snapshot', () async {
    expect(
      await cache.save(
        GgufDiscoveryResult(
          assessments: <GgufCandidateAssessment>[_candidate()],
          sourceFailures: const <GgufDiscoverySourceFailure>[],
        ),
        discoveredAtUtc: DateTime.utc(2026, 8, 27, 5, 2),
      ),
      isTrue,
    );

    final DateTime newerTimestamp = DateTime.utc(2026, 8, 27, 6, 15);
    expect(
      await cache.save(
        GgufDiscoveryResult(
          assessments: const <GgufCandidateAssessment>[],
          sourceFailures: const <GgufDiscoverySourceFailure>[],
        ),
        discoveredAtUtc: newerTimestamp,
      ),
      isTrue,
    );

    final GgufDiscoveryCacheEntry? restored = await cache.load();
    expect(restored, isNotNull);
    final GgufDiscoveryCacheEntry entry = restored!;
    expect(entry.discoveredAtUtc, newerTimestamp);
    expect(entry.result.assessments, isEmpty);
  });

  test('invalid cache data is ignored', () async {
    expect(
      await cache.save(
        GgufDiscoveryResult(
          assessments: <GgufCandidateAssessment>[_candidate()],
          sourceFailures: const <GgufDiscoverySourceFailure>[],
        ),
        discoveredAtUtc: DateTime.utc(2026, 8, 27, 5, 2),
      ),
      isTrue,
    );
    final File cacheFile = await temporaryDirectory
        .list()
        .where((FileSystemEntity entity) => entity is File)
        .cast<File>()
        .single;
    await cacheFile.writeAsString('{not valid json', flush: true);

    expect(await cache.load(), isNull);
  });
}

GgufCandidateAssessment _candidate() {
  return GgufCandidateAssessment(
    repositoryId: 'Qwen/Qwen2.5-3B-Instruct-GGUF',
    disposition: GgufCandidateDisposition.candidate,
    reasons: const <String>[],
    warnings: const <String>[
      'Review qwen-research terms before download.',
    ],
    artifact: GgufCandidateArtifact(
      repositoryId: 'Qwen/Qwen2.5-3B-Instruct-GGUF',
      commitSha: '0123456789abcdef0123456789abcdef01234567',
      fileName: 'qwen2.5-3b-instruct-q4_k_m.gguf',
      sizeBytes: 2100000000,
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      downloadUri: Uri.parse(
        'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/'
        '0123456789abcdef0123456789abcdef01234567/'
        'qwen2.5-3b-instruct-q4_k_m.gguf',
      ),
      sourcePage: Uri.parse(
        'https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF',
      ),
      license: 'qwen-research',
      licenseSourceRepository: 'Qwen/Qwen2.5-3B-Instruct-GGUF',
      hasCustomLicense: true,
      modelFamily: 'Qwen/ChatML',
      promptFormat: PromptFormat.chatml,
    ),
  );
}
