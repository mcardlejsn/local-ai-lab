import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/gguf_candidate_assessment.dart';
import 'package:local_ai_summarizer/services/gguf_discovery_service.dart';
import 'package:local_ai_summarizer/services/hugging_face_discovery_service.dart';

void main() {
  group('GGUF discovery orchestration', () {
    test('does not contact Hugging Face when constructed', () {
      int requests = 0;

      GgufDiscoveryService(
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            requests++;
            return <Object?>[];
          },
        ),
      );

      expect(requests, 0);
    });

    test('searches, retrieves exact metadata, and screens a candidate',
        () async {
      final List<Uri> requests = <Uri>[];
      final GgufDiscoveryService service = GgufDiscoveryService(
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
      expect(result.needsReviewCount, 0);
      expect(result.rejectedCount, 0);
      expect(result.sourceFailures, isEmpty);
    });

    test('fetches and caches one shared upstream license repository', () async {
      final List<String> requestedPaths = <String>[];
      final GgufDiscoveryService service = GgufDiscoveryService(
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

      expect(result.assessments, hasLength(2));
      expect(result.candidateCount, 2);
      expect(result.sourceFailures, isEmpty);
      expect(
        requestedPaths
            .where((path) => path == '/api/models/Qwen/Qwen2.5-1.5B-Instruct')
            .length,
        1,
      );
    });

    test('continues after one candidate-detail request fails', () async {
      final GgufDiscoveryService service = GgufDiscoveryService(
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

    test('records an upstream failure and retains Needs review', () async {
      final GgufDiscoveryService service = GgufDiscoveryService(
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

      expect(result.assessments, hasLength(1));
      expect(
        result.assessments.single.disposition,
        GgufCandidateDisposition.needsReview,
      );
      expect(result.assessments.single.canDownload, isFalse);
      expect(result.needsReviewCount, 1);
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
  });
}

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
