import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/gguf_candidate_assessment.dart';
import 'package:local_ai_summarizer/models/gguf_compatibility_policy.dart';
import 'package:local_ai_summarizer/models/gguf_discovery_result.dart';
import 'package:local_ai_summarizer/models/model_catalog.dart';
import 'package:local_ai_summarizer/services/gguf_discovery_service.dart';
import 'package:local_ai_summarizer/services/hugging_face_discovery_service.dart';

void main() {
  group('GGUF discovery orchestration', () {
    test('does not contact Hugging Face when constructed', () {
      int requests = 0;
      int seedLoads = 0;

      GgufDiscoveryService(
        loadSeedRepositories: () async {
          seedLoads++;
          return const <String>[];
        },
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            requests++;
            return <Object?>[];
          },
        ),
      );

      expect(requests, 0);
      expect(seedLoads, 0);
    });

    test('searches, retrieves exact metadata, and screens a candidate',
        () async {
      final List<Uri> requests = <Uri>[];
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: _noSeeds,
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            requests.add(uri);
            if (uri.path == '/api/models') {
              return <Object?>[
                _summary('Qwen/Qwen2.5-1.5B-Instruct-GGUF'),
              ];
            }
            return _repository(
              id: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
              license: 'apache-2.0',
              fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
            );
          },
        ),
      );

      final result = await service.discover(limit: 7);

      expect(requests, hasLength(2));
      expect(requests.first.queryParameters['limit'], '7');
      expect(result.assessments, hasLength(1));
      expect(
        result.assessments.single.disposition,
        GgufCandidateDisposition.candidate,
      );
      expect(result.assessments.single.canDownload, isTrue);
      expect(result.candidateCount, 1);
      expect(result.sourceFailures, isEmpty);
    });

    test('keeps the first passing repository for one shared base model',
        () async {
      final List<String> requestedPaths = <String>[];
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: _noSeeds,
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            requestedPaths.add(uri.path);
            if (uri.path == '/api/models') {
              return <Object?>[
                _summary('Publisher/First-Qwen2.5-Instruct-GGUF'),
                _summary('Publisher/Second-Qwen2.5-Instruct-GGUF'),
              ];
            }
            if (uri.path ==
                '/api/models/Publisher/First-Qwen2.5-Instruct-GGUF') {
              return _repository(
                id: 'Publisher/First-Qwen2.5-Instruct-GGUF',
                fileName: 'qwen2.5-first-instruct-q4_k_m.gguf',
                upstreamId: 'Qwen/Qwen2.5-1.5B-Instruct',
              );
            }
            if (uri.path ==
                '/api/models/Publisher/Second-Qwen2.5-Instruct-GGUF') {
              return _repository(
                id: 'Publisher/Second-Qwen2.5-Instruct-GGUF',
                fileName: 'qwen2.5-second-instruct-q4_k_m.gguf',
                upstreamId: 'Qwen/Qwen2.5-1.5B-Instruct',
              );
            }
            if (uri.path == '/api/models/Qwen/Qwen2.5-1.5B-Instruct') {
              return _repository(
                id: 'Qwen/Qwen2.5-1.5B-Instruct',
                license: 'apache-2.0',
              );
            }
            throw StateError('Unexpected request: $uri');
          },
        ),
      );

      final result = await service.discover();

      expect(result.assessments, hasLength(1));
      expect(
        result.assessments.single.repositoryId,
        'Publisher/First-Qwen2.5-Instruct-GGUF',
      );
      expect(result.candidateCount, 1);
      expect(result.sourceFailures, isEmpty);
      expect(
        requestedPaths
            .where((path) => path == '/api/models/Qwen/Qwen2.5-1.5B-Instruct')
            .length,
        1,
      );
    });

    test('prefers a seed for a case-insensitive shared base model',
        () async {
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: () async => <String>[
          'Seed/Qwen2.5-1.5B-Instruct-GGUF',
        ],
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            if (uri.path == '/api/models') {
              return <Object?>[
                _summary('Live/Qwen2.5-1.5B-Instruct-GGUF'),
              ];
            }
            if (uri.path ==
                '/api/models/Seed/Qwen2.5-1.5B-Instruct-GGUF') {
              return _repository(
                id: 'Seed/Qwen2.5-1.5B-Instruct-GGUF',
                license: 'apache-2.0',
                fileName: 'seed-qwen2.5-1.5b-instruct-q4_k_m.gguf',
                upstreamId: 'Qwen/Qwen2.5-1.5B-Instruct',
              );
            }
            if (uri.path ==
                '/api/models/Live/Qwen2.5-1.5B-Instruct-GGUF') {
              return _repository(
                id: 'Live/Qwen2.5-1.5B-Instruct-GGUF',
                license: 'apache-2.0',
                fileName: 'live-qwen2.5-1.5b-instruct-q4_k_m.gguf',
                upstreamId: 'qwen/qwen2.5-1.5b-instruct',
              );
            }
            throw StateError('Unexpected request: $uri');
          },
        ),
      );

      final result = await service.discover();

      expect(result.assessments, hasLength(1));
      expect(
        result.assessments.single.repositoryId,
        'Seed/Qwen2.5-1.5B-Instruct-GGUF',
      );
    });

    test('continues after one candidate-detail request fails', () async {
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: _noSeeds,
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            if (uri.path == '/api/models') {
              return <Object?>[
                _summary('Broken/Model-Instruct-GGUF'),
                _summary('Qwen/Working-Instruct-GGUF'),
              ];
            }
            if (uri.path == '/api/models/Broken/Model-Instruct-GGUF') {
              throw const HuggingFaceDiscoveryException(
                'The repository metadata was unavailable.',
              );
            }
            return _repository(
              id: 'Qwen/Working-Instruct-GGUF',
              license: 'mit',
              fileName: 'qwen2.5-working-instruct-q4_k_m.gguf',
            );
          },
        ),
      );

      final result = await service.discover();

      expect(result.assessments, hasLength(1));
      expect(result.candidateCount, 1);
      expect(result.sourceFailures, hasLength(1));
      expect(
        result.sourceFailures.single.repositoryId,
        'Broken/Model-Instruct-GGUF',
      );
      expect(result.sourceFailures.single.requestedForRepositoryId, isNull);
      expect(result.sourceFailures.single.message, contains('unavailable'));
    });

    test('records an upstream failure without returning Needs review',
        () async {
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: _noSeeds,
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            if (uri.path == '/api/models') {
              return <Object?>[
                _summary('Publisher/Qwen2.5-Instruct-GGUF'),
              ];
            }
            if (uri.path == '/api/models/Publisher/Qwen2.5-Instruct-GGUF') {
              return _repository(
                id: 'Publisher/Qwen2.5-Instruct-GGUF',
                fileName: 'qwen2.5-instruct-q4_k_m.gguf',
                upstreamId: 'Qwen/Qwen2.5-1.5B-Instruct',
              );
            }
            throw const HuggingFaceDiscoveryException(
              'The upstream metadata request failed.',
            );
          },
        ),
      );

      final result = await service.discover();

      expect(result.assessments, isEmpty);
      expect(result.candidateCount, 0);
      expect(result.sourceFailures, hasLength(1));
      expect(
        result.sourceFailures.single.repositoryId,
        'Qwen/Qwen2.5-1.5B-Instruct',
      );
      expect(
        result.sourceFailures.single.requestedForRepositoryId,
        'Publisher/Qwen2.5-Instruct-GGUF',
      );
    });

    test('skips duplicate search entries case-insensitively', () async {
      int detailRequests = 0;
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: _noSeeds,
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            if (uri.path == '/api/models') {
              return <Object?>[
                _summary('Qwen/Qwen2.5-Instruct-GGUF'),
                _summary('qwen/qwen2.5-instruct-gguf'),
              ];
            }
            detailRequests++;
            return _repository(
              id: 'Qwen/Qwen2.5-Instruct-GGUF',
              license: 'apache-2.0',
              fileName: 'qwen2.5-instruct-q4_k_m.gguf',
            );
          },
        ),
      );

      final result = await service.discover();

      expect(detailRequests, 1);
      expect(result.assessments, hasLength(1));
    });

    test('merges seeds first and deduplicates live repositories', () async {
      final List<String> detailPaths = <String>[];
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: () async => <String>[
          'Seed/Qwen2.5-1B-Instruct-GGUF',
        ],
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            if (uri.path == '/api/models') {
              expect(uri.queryParameters['limit'], '50');
              return <Object?>[
                _summary('seed/qwen2.5-1b-instruct-gguf'),
                _summary('Live/Qwen2.5-2B-Instruct-GGUF'),
              ];
            }
            detailPaths.add(uri.path);
            final String id = uri.pathSegments.skip(2).join('/');
            return _repository(
              id: id,
              license: 'apache-2.0',
              fileName: '${id.split('/').last.toLowerCase()}-q4_k_m.gguf',
            );
          },
        ),
      );

      final result = await service.discover();

      expect(
        detailPaths,
        <String>[
          '/api/models/Seed/Qwen2.5-1B-Instruct-GGUF',
          '/api/models/Live/Qwen2.5-2B-Instruct-GGUF',
        ],
      );
      expect(result.candidateCount, 2);
    });

    test('returns Candidates only after screening', () async {
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: _noSeeds,
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            if (uri.path == '/api/models') {
              return <Object?>[
                _summary('Publisher/Unknown-1B-Instruct-GGUF'),
                _summary('Qwen/Qwen3.5-2B-Instruct-GGUF'),
                _summary('Qwen/Downloadable-1B-Instruct-GGUF'),
              ];
            }
            if (uri.path.contains('Unknown')) {
              return _repository(
                id: 'Publisher/Unknown-1B-Instruct-GGUF',
                license: 'mit',
                fileName: 'unknown-1b-instruct-q4_k_m.gguf',
              );
            }
            if (uri.path.contains('Qwen3.5')) {
              return _repository(
                id: 'Qwen/Qwen3.5-2B-Instruct-GGUF',
                license: 'apache-2.0',
                fileName: 'qwen3.5-2b-instruct-q4_k_m.gguf',
              );
            }
            return _repository(
              id: 'Qwen/Downloadable-1B-Instruct-GGUF',
              license: 'apache-2.0',
              fileName: 'qwen2.5-downloadable-1b-instruct-q4_k_m.gguf',
            );
          },
        ),
      );

      final result = await service.discover();

      expect(result.assessments, hasLength(1));
      expect(
        result.assessments.single.repositoryId,
        'Qwen/Downloadable-1B-Instruct-GGUF',
      );
      expect(result.assessments.single.canDownload, isTrue);
    });

    test('omits an exact artifact already in the Verified catalog', () async {
      const String repositoryId = 'Qwen/Verified-1B-Instruct-GGUF';
      const String fileName = 'qwen2.5-verified-1b-instruct-q4_k_m.gguf';
      const String sha256 =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: () async => <String>[repositoryId],
        verifiedCatalog: const <CatalogModel>[
          CatalogModel(
            id: 'verified-test',
            displayName: 'Verified test model',
            fileName: fileName,
            url: 'https://huggingface.co/Qwen/Verified-1B-Instruct-GGUF/'
                'resolve/0123456789abcdef0123456789abcdef01234567/'
                'qwen2.5-verified-1b-instruct-q4_k_m.gguf',
            sizeBytes: 1000000000,
            sha256: sha256,
            license: 'Apache-2.0',
            sourcePage: 'https://huggingface.co/Qwen/Verified-1B-Instruct-GGUF',
          ),
        ],
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            if (uri.path == '/api/models') return <Object?>[];
            return _repository(
              id: repositoryId,
              license: 'apache-2.0',
              fileName: fileName,
            );
          },
        ),
      );

      final result = await service.discover();

      expect(result.assessments, isEmpty);
      expect(result.candidateCount, 0);
    });

    test('pins and excludes only the qualified Falcon-H1 artifact', () {
      final CatalogModel model = kModelCatalog.singleWhere(
        (CatalogModel candidate) =>
            candidate.id == 'falcon-h1-0.5b-instruct-q4_k_m',
      );
      expect(model.displayName, 'Falcon-H1 0.5B Instruct (Q4_K_M)');
      expect(model.fileName, 'Falcon-H1-0.5B-Instruct-Q4_K_M.gguf');
      expect(
        model.url,
        'https://huggingface.co/tiiuae/Falcon-H1-0.5B-Instruct-GGUF/'
        'resolve/9bf0c2d4391cf4850aa62bfee1d8fe71afba8be2/'
        'Falcon-H1-0.5B-Instruct-Q4_K_M.gguf',
      );
      expect(model.sizeBytes, 314806560);
      expect(
        model.sha256,
        '138a37a94b9e313af4e22d4af46b8119b76a31afdd61cabbeae7010ae45d2ac6',
      );
      expect(model.license, 'Falcon-LLM License');
      expect(
        model.sourcePage,
        'https://huggingface.co/tiiuae/Falcon-H1-0.5B-Instruct-GGUF',
      );

      const String differentSha256 =
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
      final GgufDiscoveryResult filtered = GgufDiscoveryService(
        loadSeedRepositories: _noSeeds,
      ).excludeVerifiedArtifacts(
        GgufDiscoveryResult(
          assessments: <GgufCandidateAssessment>[
            _falconCandidate(model),
            _falconCandidate(model, sha256: differentSha256),
          ],
          sourceFailures: const <GgufDiscoverySourceFailure>[],
        ),
      );

      expect(filtered.assessments, hasLength(1));
      expect(filtered.assessments.single.artifact!.sha256, differentSha256);
    });

    test('rejects an uncontrolled live search limit', () async {
      int seedLoads = 0;
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: () async {
          seedLoads++;
          return const <String>[];
        },
      );

      await expectLater(
        service.discover(limit: 51),
        throwsArgumentError,
      );
      expect(seedLoads, 0);
    });
  });
}

GgufCandidateAssessment _falconCandidate(
  CatalogModel model, {
  String? sha256,
}) {
  const String repositoryId = 'tiiuae/Falcon-H1-0.5B-Instruct-GGUF';
  return GgufCandidateAssessment(
    repositoryId: repositoryId,
    disposition: GgufCandidateDisposition.candidate,
    reasons: const <String>[],
    warnings: const <String>[],
    artifact: GgufCandidateArtifact(
      repositoryId: repositoryId,
      commitSha: '9bf0c2d4391cf4850aa62bfee1d8fe71afba8be2',
      fileName: model.fileName,
      sizeBytes: model.sizeBytes,
      sha256: sha256 ?? model.sha256,
      downloadUri: model.uri,
      sourcePage: Uri.parse(model.sourcePage),
      license: model.license,
      licenseSourceRepository: repositoryId,
      hasCustomLicense: true,
      modelFamily: 'Falcon-H1 0.5B',
      promptFormat: PromptFormat.falconH1,
    ),
  );
}

Future<List<String>> _noSeeds() async => const <String>[];

Map<String, Object?> _summary(String id) {
  return <String, Object?>{
    'id': id,
    'private': false,
    'gated': false,
    'tags': <String>['gguf', 'conversational'],
  };
}

Map<String, Object?> _repository({
  required String id,
  String? license,
  String? fileName,
  String? upstreamId,
}) {
  final List<String> tags = <String>['gguf', 'conversational'];
  if (upstreamId != null) {
    tags.add('base_model:quantized:$upstreamId');
  }
  return <String, Object?>{
    'id': id,
    'sha': '0123456789abcdef0123456789abcdef01234567',
    'private': false,
    'gated': false,
    'tags': tags,
    'cardData': <String, Object?>{
      if (license != null) 'license': license,
      if (upstreamId != null) ...<String, Object?>{
        'base_model_relation': 'quantized',
        'base_model': upstreamId,
      },
    },
    'siblings': <Object?>[
      if (fileName != null)
        <String, Object?>{
          'rfilename': fileName,
          'size': 1000000000,
          'lfs': <String, Object?>{
            'sha256':
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'size': 1000000000,
          },
        },
    ],
  };
}
