import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/services/gguf_discovery_seed_service.dart';

void main() {
  group('GGUF discovery seed service', () {
    test('does not read the bundled list when constructed', () {
      int loads = 0;

      GgufDiscoverySeedService(
        loadText: () async {
          loads++;
          return '';
        },
      );

      expect(loads, 0);
    });

    test('parses comments, blank lines, and case-insensitive duplicates',
        () async {
      final GgufDiscoverySeedService service = GgufDiscoverySeedService(
        loadText: () async => '''
# Maintained repositories

Qwen/Qwen2.5-1.5B-Instruct-GGUF
qwen/qwen2.5-1.5b-instruct-gguf
tiiuae/Falcon-H1-0.5B-Instruct-GGUF
''',
      );

      final List<String> repositories = await service.loadRepositoryIds();

      expect(
        repositories,
        <String>[
          'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
          'tiiuae/Falcon-H1-0.5B-Instruct-GGUF',
        ],
      );
    });

    test('rejects an invalid repository identifier', () async {
      final GgufDiscoverySeedService service = GgufDiscoverySeedService(
        loadText: () async => 'not-an-owner-name',
      );

      await expectLater(
        service.loadRepositoryIds(),
        throwsA(
          isA<GgufDiscoverySeedException>().having(
            (GgufDiscoverySeedException error) => error.message,
            'message',
            contains('line 1'),
          ),
        ),
      );
    });

    test('rejects more repositories than the configured bound', () async {
      final String text = List<String>.generate(
        21,
        (int index) => 'Owner/Model-$index',
      ).join('\n');
      final GgufDiscoverySeedService service = GgufDiscoverySeedService(
        loadText: () async => text,
      );

      await expectLater(
        service.loadRepositoryIds(),
        throwsA(
          isA<GgufDiscoverySeedException>().having(
            (GgufDiscoverySeedException error) => error.message,
            'message',
            contains('20-repository limit'),
          ),
        ),
      );
    });

    test('reports a bundled asset load failure', () async {
      final GgufDiscoverySeedService service = GgufDiscoverySeedService(
        loadText: () async => throw StateError('missing'),
      );

      await expectLater(
        service.loadRepositoryIds(),
        throwsA(
          isA<GgufDiscoverySeedException>().having(
            (GgufDiscoverySeedException error) => error.message,
            'message',
            contains('could not be loaded'),
          ),
        ),
      );
    });
  });
}
