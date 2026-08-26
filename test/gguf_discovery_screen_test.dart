import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/screens/gguf_discovery_screen.dart';
import 'package:local_ai_summarizer/services/gguf_discovery_service.dart';
import 'package:local_ai_summarizer/services/hugging_face_discovery_service.dart';
import 'package:local_ai_summarizer/services/model_download_service.dart';

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

    testWidgets('Candidate download requires confirmation and stays Candidate',
        (WidgetTester tester) async {
      int requests = 0;
      int rescans = 0;
      final _FakeModelDownloadService downloader = _FakeModelDownloadService();
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
          home: GgufDiscoveryScreen(
            discoveryService: service,
            downloadService: downloader,
            onModelInstalled: () async {
              rescans++;
            },
          ),
        ),
      );
      expect(requests, 0);

      await tester.tap(find.byKey(const Key('discover-gguf-button')));
      await tester.pumpAndSettle();

      expect(requests, 2);
      expect(find.text('Qwen/Qwen2.5-1.5B-Instruct-GGUF'), findsOneWidget);
      expect(find.text('Candidate — not device verified'), findsOneWidget);
      expect(find.textContaining('Candidate 1'), findsOneWidget);

      const Key downloadKey = Key(
        'candidate-download-qwen2.5-1.5b-instruct-q4_k_m.gguf',
      );
      await _scrollAndTap(tester, find.byKey(downloadKey));

      expect(downloader.downloadCalls, 0);
      expect(find.text('Download Candidate?'), findsOneWidget);
      expect(
          find.textContaining('has not been device verified'), findsOneWidget);
      final Finder dialog = find.byType(AlertDialog);
      expect(
          find.descendant(
            of: dialog,
            matching: find.text('qwen2.5-1.5b-instruct-q4_k_m.gguf'),
          ),
          findsOneWidget);
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('Apache-2.0'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('confirm-candidate-download-button')),
      );
      await tester.pumpAndSettle();

      expect(downloader.downloadCalls, 1);
      expect(rescans, 1);
      expect(
        find.text('Installed Candidate — benchmark required'),
        findsOneWidget,
      );
    });

    testWidgets('custom-license Candidate warns before download',
        (WidgetTester tester) async {
      final _FakeModelDownloadService downloader = _FakeModelDownloadService();
      final GgufDiscoveryService service = GgufDiscoveryService(
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            if (uri.path == '/api/models') {
              return <Object?>[
                _summary('Qwen/Custom-License-1.5B-Instruct-GGUF'),
              ];
            }
            return _repository(
              id: 'Qwen/Custom-License-1.5B-Instruct-GGUF',
              license: 'custom-local-ai-license',
              fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
            );
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(
            discoveryService: service,
            downloadService: downloader,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('discover-gguf-button')));
      await tester.pumpAndSettle();

      const Key downloadKey = Key(
        'candidate-download-qwen2.5-1.5b-instruct-q4_k_m.gguf',
      );
      await _scrollAndTap(tester, find.byKey(downloadKey));

      expect(find.textContaining('Custom license'), findsWidgets);
      expect(find.textContaining('review its terms'), findsOneWidget);
      expect(downloader.downloadCalls, 0);
    });

    testWidgets('different same-named file blocks Candidate download',
        (WidgetTester tester) async {
      final _FakeModelDownloadService downloader = _FakeModelDownloadService(
        status: InstalledArtifactStatus.differentFile,
      );
      final GgufDiscoveryService service = _singleCandidateService();

      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(
            discoveryService: service,
            downloadService: downloader,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('discover-gguf-button')));
      await tester.pumpAndSettle();

      final Finder conflict = find.textContaining(
        'A different file already uses this exact model filename',
      );
      await tester.scrollUntilVisible(conflict, 250);
      expect(conflict, findsOneWidget);
      expect(find.text('Download'), findsNothing);
      expect(downloader.downloadCalls, 0);
    });

    testWidgets('partial Candidate can resume or be discarded',
        (WidgetTester tester) async {
      final _FakeModelDownloadService downloader = _FakeModelDownloadService(
        partial: 125000000,
      );
      final GgufDiscoveryService service = _singleCandidateService();

      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(
            discoveryService: service,
            downloadService: downloader,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('discover-gguf-button')));
      await tester.pumpAndSettle();

      const Key discardKey = Key(
        'candidate-discard-qwen2.5-1.5b-instruct-q4_k_m.gguf',
      );
      await tester.scrollUntilVisible(find.byKey(discardKey), 250);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.textContaining('Partial download: 125 MB'), findsOneWidget);

      await _scrollAndTap(tester, find.byKey(discardKey));

      expect(downloader.discardCalls, 1);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Resume'), findsNothing);
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

Future<void> _scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 250);
  await tester.drag(find.byType(ListView), const Offset(0, -120));
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

GgufDiscoveryService _singleCandidateService() {
  return GgufDiscoveryService(
    source: HuggingFaceDiscoveryService(
      fetchJson: (Uri uri) async {
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
}

class _FakeModelDownloadService extends ModelDownloadService {
  _FakeModelDownloadService({
    this.status = InstalledArtifactStatus.absent,
    this.partial = 0,
  });

  InstalledArtifactStatus status;
  int partial;
  int downloadCalls = 0;
  int discardCalls = 0;

  @override
  Future<InstalledArtifactStatus> installedArtifactStatus({
    required String fileName,
    required String expectedSha256,
  }) async {
    return status;
  }

  @override
  Future<int> partialBytes(String fileName) async => partial;

  @override
  Future<void> discardPartial(String fileName) async {
    discardCalls++;
    partial = 0;
  }

  @override
  Future<DownloadResult> download({
    required Uri url,
    required String fileName,
    required String expectedSha256,
    void Function(DownloadProgress progress)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    downloadCalls++;
    onProgress?.call(
      const DownloadProgress(
        receivedBytes: 1000000000,
        totalBytes: 1000000000,
      ),
    );
    status = InstalledArtifactStatus.matchesExpected;
    partial = 0;
    return const DownloadResult(DownloadOutcome.completed);
  }
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
