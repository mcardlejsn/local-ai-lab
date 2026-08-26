import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/screens/gguf_discovery_screen.dart';
import 'package:local_ai_summarizer/services/gguf_discovery_service.dart';
import 'package:local_ai_summarizer/services/hugging_face_discovery_service.dart';

void main() {
  group('GGUF discovery screen', () {
    testWidgets('opening the screen performs no network request',
        (WidgetTester tester) async {
      int requests = 0;
      final GgufDiscoveryService service = GgufDiscoveryService(
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            requests++;
            return <Object?>[];
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(discoveryService: service),
        ),
      );

      expect(requests, 0);
      expect(find.byKey(const Key('discover-gguf-button')), findsOneWidget);
      expect(find.textContaining('Opening this screen is offline'),
          findsOneWidget);
    });

    testWidgets('Discover explicitly requests and displays a Candidate',
        (WidgetTester tester) async {
      int requests = 0;
      final GgufDiscoveryService service = GgufDiscoveryService(
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            requests++;
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

      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(discoveryService: service),
        ),
      );
      expect(requests, 0);

      await tester.tap(find.byKey(const Key('discover-gguf-button')));
      await tester.pumpAndSettle();

      expect(requests, 2);
      expect(find.text('Qwen/Qwen2.5-1.5B-Instruct-GGUF'), findsOneWidget);
      expect(find.text('Candidate — not device verified'), findsOneWidget);
      expect(find.textContaining('Candidate 1'), findsOneWidget);
      expect(find.text('Download'), findsNothing);
    });

    testWidgets('renders review, rejection, and repository source errors',
        (WidgetTester tester) async {
      final GgufDiscoveryService service = GgufDiscoveryService(
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            if (uri.path == '/api/models') {
              return <Object?>[
                _summary('Publisher/Unknown-1B-Instruct-GGUF'),
                _summary('Qwen/Qwen3.5-2B-Instruct-GGUF'),
                _summary('Broken/Unavailable-Instruct-GGUF'),
              ];
            }
            if (uri.path == '/api/models/Publisher/Unknown-1B-Instruct-GGUF') {
              return _repository(
                id: 'Publisher/Unknown-1B-Instruct-GGUF',
                license: 'mit',
                fileName: 'unknown-1b-instruct-q4_k_m.gguf',
              );
            }
            if (uri.path == '/api/models/Qwen/Qwen3.5-2B-Instruct-GGUF') {
              return _repository(
                id: 'Qwen/Qwen3.5-2B-Instruct-GGUF',
                license: 'apache-2.0',
                fileName: 'qwen3.5-2b-instruct-q4_k_m.gguf',
              );
            }
            throw const HuggingFaceDiscoveryException(
              'Repository metadata unavailable.',
            );
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(discoveryService: service),
        ),
      );
      await tester.tap(find.byKey(const Key('discover-gguf-button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Needs review 1'), findsOneWidget);
      expect(find.textContaining('Rejected 1'), findsOneWidget);
      expect(find.textContaining('Source errors 1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Broken/Unavailable-Instruct-GGUF'),
        300,
      );
      expect(find.text('Broken/Unavailable-Instruct-GGUF'), findsOneWidget);
      expect(find.text('Repository metadata unavailable.'), findsOneWidget);
    });

    testWidgets('shows a search failure without inventing model results',
        (WidgetTester tester) async {
      final GgufDiscoveryService service = GgufDiscoveryService(
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            throw const HuggingFaceDiscoveryException(
              'Hugging Face is temporarily unavailable.',
            );
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(discoveryService: service),
        ),
      );
      await tester.tap(find.byKey(const Key('discover-gguf-button')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Hugging Face is temporarily unavailable.'),
        findsOneWidget,
      );
      expect(find.textContaining('Candidate 0'), findsNothing);
      expect(find.byKey(const Key('discover-gguf-button')), findsOneWidget);
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
  required String license,
  required String fileName,
}) {
  return <String, Object?>{
    'id': id,
    'sha': '0123456789abcdef0123456789abcdef01234567',
    'private': false,
    'gated': false,
    'tags': <String>['gguf', 'conversational'],
    'cardData': <String, Object?>{'license': license},
    'siblings': <Object?>[
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
