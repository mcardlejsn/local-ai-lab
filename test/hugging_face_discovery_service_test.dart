import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/services/hugging_face_discovery_service.dart';

void main() {
  group('Hugging Face discovery service', () {
    test('does not make a request when constructed', () {
      int requests = 0;

      HuggingFaceDiscoveryService(
        fetchJson: (Uri uri) async {
          requests++;
          return <Object?>[];
        },
      );

      expect(requests, 0);
    });

    test(
      'searches popular matching GGUF repos and excludes restrictions',
      () async {
        Uri? requestedUri;
        final HuggingFaceDiscoveryService service = HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            requestedUri = uri;
            return <Object?>[
              <String, Object?>{
                'id': 'Example/Public-GGUF',
                'private': false,
                'tags': <String>['gguf', 'conversational'],
                'lastModified': '2026-08-25T12:00:00.000Z',
              },
              <String, Object?>{
                'id': 'Example/Gated-GGUF',
                'private': false,
                'gated': 'manual',
                'tags': <String>['gguf'],
              },
              <String, Object?>{
                'id': 'Example/Private-GGUF',
                'private': true,
                'gated': false,
                'tags': <String>['gguf'],
              },
            ];
          },
        );

        final results = await service.searchPublicGgufRepositories(
          searchTerm: 'chat',
          limit: 12,
        );

        expect(results, hasLength(1));
        expect(results.single.id, 'Example/Public-GGUF');
        expect(results.single.isPublicAndUngated, isTrue);
        expect(requestedUri?.host, 'huggingface.co');
        expect(requestedUri?.path, '/api/models');
        expect(requestedUri?.queryParameters['filter'], 'gguf');
        expect(
          requestedUri?.queryParameters['pipeline_tag'],
          'text-generation',
        );
        expect(requestedUri?.queryParameters['search'], 'chat');
        expect(requestedUri?.queryParameters['gated'], 'false');
        expect(requestedUri?.queryParameters['sort'], 'downloads');
        expect(requestedUri?.queryParameters['direction'], '-1');
        expect(requestedUri?.queryParameters['limit'], '12');
      },
    );

    test('requests the maximum supported page by default', () async {
      Uri? requestedUri;
      final HuggingFaceDiscoveryService service = HuggingFaceDiscoveryService(
        fetchJson: (Uri uri) async {
          requestedUri = uri;
          return <Object?>[];
        },
      );

      await service.searchPublicGgufRepositories();

      expect(requestedUri?.queryParameters['limit'], '50');
      expect(requestedUri?.queryParameters['search'], 'instruct');
    });

    test(
      'parses exact repository, license, upstream, and blob metadata',
      () async {
        Uri? requestedUri;
        final HuggingFaceDiscoveryService service = HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            requestedUri = uri;
            return <String, Object?>{
              'id': 'Publisher/Example-GGUF',
              'sha': '0123456789abcdef0123456789abcdef01234567',
              'private': false,
              'lastModified': '2026-08-26T12:30:00.000Z',
              'tags': <String>[
                'gguf',
                'base_model:quantized:Upstream/Example-Instruct',
              ],
              'cardData': <String, Object?>{
                'license': 'other',
                'license_name': 'Example Community License',
                'base_model_relation': 'quantized',
                'base_model': 'Upstream/Example-Instruct',
              },
              'siblings': <Object?>[
                <String, Object?>{
                  'rfilename': 'example-Q4_K_M.gguf',
                  'size': 123456789,
                  'lfs': <String, Object?>{
                    'sha256':
                        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                    'size': 123456789,
                  },
                },
                <String, Object?>{'rfilename': 'README.md'},
              ],
            };
          },
        );

        final metadata = await service.getRepositoryMetadata(
          'Publisher/Example-GGUF',
        );

        expect(metadata.id, 'Publisher/Example-GGUF');
        expect(metadata.commitSha, '0123456789abcdef0123456789abcdef01234567');
        expect(metadata.isPublicAndUngated, isTrue);
        expect(metadata.declaredLicenseLabel, 'Example Community License');
        expect(metadata.quantizedBaseModels, <String>[
          'Upstream/Example-Instruct',
        ]);
        expect(metadata.files, hasLength(2));
        expect(metadata.files.first.path, 'example-Q4_K_M.gguf');
        expect(metadata.files.first.sizeBytes, 123456789);
        expect(
          metadata.files.first.sha256,
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        );
        expect(requestedUri?.path, '/api/models/Publisher/Example-GGUF');
        expect(requestedUri?.queryParameters['blobs'], 'true');
      },
    );

    test('rejects incomplete exact repository metadata', () async {
      final HuggingFaceDiscoveryService service = HuggingFaceDiscoveryService(
        fetchJson: (Uri uri) async => <String, Object?>{
          'id': 'Publisher/Example-GGUF',
          'private': false,
          'gated': false,
          'tags': <String>['gguf'],
          'siblings': <Object?>[],
        },
      );

      await expectLater(
        service.getRepositoryMetadata('Publisher/Example-GGUF'),
        throwsA(
          isA<HuggingFaceDiscoveryException>().having(
            (error) => error.message,
            'message',
            contains('sha'),
          ),
        ),
      );
    });

    test('rejects a malformed gated status', () async {
      final HuggingFaceDiscoveryService service = HuggingFaceDiscoveryService(
        fetchJson: (Uri uri) async => <Object?>[
          <String, Object?>{
            'id': 'Example/Invalid-GGUF',
            'private': false,
            'gated': 7,
            'tags': <String>['gguf'],
          },
        ],
      );

      await expectLater(
        service.searchPublicGgufRepositories(),
        throwsA(
          isA<HuggingFaceDiscoveryException>().having(
            (error) => error.message,
            'message',
            contains('invalid gated status'),
          ),
        ),
      );
    });

    test(
      'rejects an invalid repository identifier before requesting',
      () async {
        int requests = 0;
        final HuggingFaceDiscoveryService service = HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            requests++;
            return <String, Object?>{};
          },
        );

        await expectLater(
          service.getRepositoryMetadata('not-an-owner-name'),
          throwsArgumentError,
        );
        expect(requests, 0);
      },
    );

    test('enforces the bounded search limit before requesting', () async {
      int requests = 0;
      final HuggingFaceDiscoveryService service = HuggingFaceDiscoveryService(
        fetchJson: (Uri uri) async {
          requests++;
          return <Object?>[];
        },
      );

      await expectLater(
        service.searchPublicGgufRepositories(limit: 51),
        throwsArgumentError,
      );
      expect(requests, 0);
    });

    test('rejects an empty search term before requesting', () async {
      int requests = 0;
      final HuggingFaceDiscoveryService service = HuggingFaceDiscoveryService(
        fetchJson: (Uri uri) async {
          requests++;
          return <Object?>[];
        },
      );

      await expectLater(
        service.searchPublicGgufRepositories(searchTerm: '   '),
        throwsArgumentError,
      );
      expect(requests, 0);
    });
  });
}
