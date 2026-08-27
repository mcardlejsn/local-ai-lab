import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/gguf_candidate_assessment.dart';
import 'package:local_ai_summarizer/models/gguf_compatibility_policy.dart';
import 'package:local_ai_summarizer/models/gguf_discovery_result.dart';
import 'package:local_ai_summarizer/models/model_catalog.dart';
import 'package:local_ai_summarizer/screens/gguf_discovery_screen.dart';
import 'package:local_ai_summarizer/services/database_service.dart';
import 'package:local_ai_summarizer/services/gguf_discovery_cache_service.dart';
import 'package:local_ai_summarizer/services/gguf_discovery_service.dart';
import 'package:local_ai_summarizer/services/hugging_face_discovery_service.dart';
import 'package:local_ai_summarizer/services/model_download_service.dart';

void main() {
  group('GGUF discovery screen', () {
    testWidgets('opening the screen performs no network request',
        (WidgetTester tester) async {
      int requests = 0;
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: _noSeeds,
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            requests++;
            return <Object?>[];
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(
            discoveryService: service,
            discoveryCache: _FakeGgufDiscoveryCache(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(requests, 0);
      expect(find.byKey(const Key('discover-gguf-button')), findsOneWidget);
      expect(find.textContaining('Opening this screen is offline'),
          findsOneWidget);
    });

    testWidgets('Candidate download requires confirmation and stays Candidate',
        (WidgetTester tester) async {
      int requests = 0;
      int rescans = 0;
      Uri? openedLicenseUri;
      final _FakeModelDownloadService downloader = _FakeModelDownloadService();
      final _FakeGgufDiscoveryCache cache = _FakeGgufDiscoveryCache();
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: _noSeeds,
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
            discoveryCache: cache,
            downloadService: downloader,
            externalUriLauncher: (Uri uri) async {
              openedLicenseUri = uri;
              return true;
            },
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
      expect(cache.saveCalls, 1);
      expect(find.text('Qwen/Qwen2.5-1.5B-Instruct-GGUF'), findsOneWidget);
      expect(find.text('Candidate — not device verified'), findsOneWidget);
      expect(find.text('1 downloadable Candidate found'), findsOneWidget);
      expect(
        find.byKey(const Key('discovery-incomplete-warning')),
        findsNothing,
      );

      const Key licenseKey = Key(
        'candidate-license-qwen2.5-1.5b-instruct-q4_k_m.gguf',
      );
      await _scrollAndTap(tester, find.byKey(licenseKey));
      expect(find.text('View license terms'), findsOneWidget);
      expect(
        openedLicenseUri,
        Uri.parse('https://www.apache.org/licenses/LICENSE-2.0'),
      );

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

    testWidgets('installed Candidate exposes its exact benchmark action',
        (WidgetTester tester) async {
      GgufCandidateArtifact? benchmarkedArtifact;
      CandidateQualificationStatus status = CandidateQualificationStatus.notRun;
      final _FakeModelDownloadService downloader = _FakeModelDownloadService(
        status: InstalledArtifactStatus.matchesExpected,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(
            discoveryService: _singleCandidateService(),
            discoveryCache: _FakeGgufDiscoveryCache(),
            downloadService: downloader,
            qualificationLookup: (String qualificationArtifactId) async {
              return status;
            },
            onBenchmarkCandidate: (GgufCandidateArtifact artifact) async {
              benchmarkedArtifact = artifact;
              status = CandidateQualificationStatus.completed;
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('discover-gguf-button')));
      await tester.pumpAndSettle();

      const String fileName = 'qwen2.5-1.5b-instruct-q4_k_m.gguf';
      const Key benchmarkKey = Key('candidate-benchmark-$fileName');
      expect(
        find.text('Installed Candidate — benchmark required'),
        findsOneWidget,
      );
      await _scrollAndTap(tester, find.byKey(benchmarkKey));

      expect(benchmarkedArtifact?.fileName, fileName);
      expect(
        benchmarkedArtifact?.qualificationArtifactId,
        'Qwen/Qwen2.5-1.5B-Instruct-GGUF@'
        '0123456789abcdef0123456789abcdef01234567/'
        'qwen2.5-1.5b-instruct-q4_k_m.gguf#'
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      expect(find.text('Benchmark Candidate'), findsOneWidget);
      expect(
        find.text('Benchmark completed — review required'),
        findsOneWidget,
      );
    });

    testWidgets('failed exact qualification requires a retry',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(
            discoveryService: _singleCandidateService(),
            discoveryCache: _FakeGgufDiscoveryCache(),
            downloadService: _FakeModelDownloadService(
              status: InstalledArtifactStatus.matchesExpected,
            ),
            qualificationLookup: (String qualificationArtifactId) async {
              return CandidateQualificationStatus.failed;
            },
            onBenchmarkCandidate: (GgufCandidateArtifact artifact) async {},
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('discover-gguf-button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Benchmark failed — retry required'),
        findsOneWidget,
      );
      expect(find.text('Benchmark Candidate'), findsOneWidget);
    });

    testWidgets('custom-license Candidate links to readable terms',
        (WidgetTester tester) async {
      final _FakeModelDownloadService downloader = _FakeModelDownloadService();
      Uri? openedUri;
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: _noSeeds,
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            if (uri.path == '/api/models') {
              return <Object?>[
                _summary('bartowski/Llama-3.2-1B-Instruct-GGUF'),
              ];
            }
            return _repository(
              id: 'bartowski/Llama-3.2-1B-Instruct-GGUF',
              license: 'llama3.2',
              fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
            );
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(
            discoveryService: service,
            discoveryCache: _FakeGgufDiscoveryCache(),
            downloadService: downloader,
            externalUriLauncher: (Uri uri) async {
              openedUri = uri;
              return true;
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('discover-gguf-button')));
      await tester.pumpAndSettle();

      const Key licenseKey = Key(
        'candidate-license-Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      );
      await _scrollAndTap(tester, find.byKey(licenseKey));
      expect(find.textContaining('Warning: Custom license'), findsNothing);
      expect(
        openedUri,
        Uri.parse('https://developer.meta.com/ai/llama3_2/license/'),
      );

      const Key downloadKey = Key(
        'candidate-download-Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      );
      await _scrollAndTap(tester, find.byKey(downloadKey));

      expect(
        find.byKey(const Key('candidate-dialog-license-terms')),
        findsOneWidget,
      );
      expect(find.textContaining('review its terms'), findsNothing);
      expect(downloader.downloadCalls, 0);
    });

    testWidgets('legacy cached custom-license warning stays hidden',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(
            discoveryService: _singleCandidateService(),
            discoveryCache: _FakeGgufDiscoveryCache(
              entry: GgufDiscoveryCacheEntry(
                result: _cachedCustomLicenseResult(),
                discoveredAtUtc: DateTime.utc(2026, 8, 27, 11, 22),
              ),
            ),
            downloadService: _FakeModelDownloadService(),
            externalUriLauncher: (Uri uri) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      const Key licenseKey = Key(
        'candidate-license-google_gemma-3-1b-it-Q4_K_M.gguf',
      );
      await tester.scrollUntilVisible(find.byKey(licenseKey), 250);
      await tester.pumpAndSettle();

      expect(find.text('View license terms'), findsOneWidget);
      expect(find.textContaining('Warning: Custom license'), findsNothing);
    });

    testWidgets('unmapped usable license links to its metadata source',
        (WidgetTester tester) async {
      Uri? openedUri;
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: _noSeeds,
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            if (uri.path == '/api/models') {
              return <Object?>[
                _summary('Publisher/Future-1B-Instruct-GGUF'),
              ];
            }
            return _repository(
              id: 'Publisher/Future-1B-Instruct-GGUF',
              license: 'future-publisher-license',
              fileName: 'qwen-future-1b-instruct-q4_k_m.gguf',
            );
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(
            discoveryService: service,
            discoveryCache: _FakeGgufDiscoveryCache(),
            downloadService: _FakeModelDownloadService(),
            externalUriLauncher: (Uri uri) async {
              openedUri = uri;
              return true;
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('discover-gguf-button')));
      await tester.pumpAndSettle();

      const Key licenseKey = Key(
        'candidate-license-qwen-future-1b-instruct-q4_k_m.gguf',
      );
      await _scrollAndTap(tester, find.byKey(licenseKey));

      expect(find.text('View license source'), findsOneWidget);
      expect(
        openedUri,
        Uri.parse(
          'https://huggingface.co/Publisher/Future-1B-Instruct-GGUF',
        ),
      );
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
            discoveryCache: _FakeGgufDiscoveryCache(),
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

    testWidgets('partial Candidate resumes without another confirmation',
        (WidgetTester tester) async {
      final _FakeModelDownloadService downloader = _FakeModelDownloadService(
        partial: 125000000,
      );
      final GgufDiscoveryService service = _singleCandidateService();

      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(
            discoveryService: service,
            discoveryCache: _FakeGgufDiscoveryCache(),
            downloadService: downloader,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('discover-gguf-button')));
      await tester.pumpAndSettle();

      const Key resumeKey = Key(
        'candidate-resume-qwen2.5-1.5b-instruct-q4_k_m.gguf',
      );
      await tester.scrollUntilVisible(find.byKey(resumeKey), 250);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.textContaining('Partial download: 125 MB'), findsOneWidget);

      await _scrollAndTap(tester, find.byKey(resumeKey));

      expect(find.text('Download Candidate?'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(downloader.downloadCalls, 1);
      expect(
        find.text('Installed Candidate — benchmark required'),
        findsOneWidget,
      );
    });

    testWidgets('stopped message appears only in the Candidate card',
        (WidgetTester tester) async {
      final _FakeModelDownloadService downloader = _FakeModelDownloadService(
        partial: 125000000,
        outcome: DownloadOutcome.cancelled,
      );
      final GgufDiscoveryService service = _singleCandidateService();

      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(
            discoveryService: service,
            discoveryCache: _FakeGgufDiscoveryCache(),
            downloadService: downloader,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('discover-gguf-button')));
      await tester.pumpAndSettle();

      const Key resumeKey = Key(
        'candidate-resume-qwen2.5-1.5b-instruct-q4_k_m.gguf',
      );
      await _scrollAndTap(tester, find.byKey(resumeKey));

      expect(
        find.text(
          'Stopped. Partial file kept — Resume continues the download.',
        ),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('partial Candidate can be discarded',
        (WidgetTester tester) async {
      final _FakeModelDownloadService downloader = _FakeModelDownloadService(
        partial: 125000000,
      );
      final GgufDiscoveryService service = _singleCandidateService();

      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(
            discoveryService: service,
            discoveryCache: _FakeGgufDiscoveryCache(),
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

    testWidgets(
        'restores cached Candidates and partial state without networking',
        (WidgetTester tester) async {
      int requests = 0;
      final _FakeGgufDiscoveryCache cache = _FakeGgufDiscoveryCache(
        entry: GgufDiscoveryCacheEntry(
          result: _cachedCandidateResult(),
          discoveredAtUtc: DateTime.utc(2026, 8, 27, 5, 2),
        ),
      );
      final _FakeModelDownloadService downloader = _FakeModelDownloadService(
        partial: 82000000,
      );
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: _noSeeds,
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async {
            requests++;
            return <Object?>[];
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(
            discoveryService: service,
            discoveryCache: cache,
            downloadService: downloader,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(requests, 0);
      expect(cache.loadCalls, 1);
      expect(find.text('1 downloadable Candidate found'), findsOneWidget);
      expect(
        find.text('Qwen/Qwen2.5-1.5B-Instruct-GGUF'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('discovery-last-refreshed')),
        findsOneWidget,
      );
      expect(find.textContaining('saved locally'), findsOneWidget);
      expect(find.textContaining('Partial download: 82 MB'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
    });

    testWidgets('failed refresh keeps the last cached Candidate visible',
        (WidgetTester tester) async {
      final _FakeGgufDiscoveryCache cache = _FakeGgufDiscoveryCache(
        entry: GgufDiscoveryCacheEntry(
          result: _cachedCandidateResult(),
          discoveredAtUtc: DateTime.utc(2026, 8, 27, 5, 2),
        ),
      );
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: _noSeeds,
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
          home: GgufDiscoveryScreen(
            discoveryService: service,
            discoveryCache: cache,
            downloadService: _FakeModelDownloadService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Qwen/Qwen2.5-1.5B-Instruct-GGUF'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('discover-gguf-button')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Hugging Face is temporarily unavailable.'),
        findsOneWidget,
      );
      expect(
        find.text('Qwen/Qwen2.5-1.5B-Instruct-GGUF'),
        findsOneWidget,
      );
      expect(cache.saveCalls, 0);
    });

    testWidgets('cached exact Verified artifacts remain excluded',
        (WidgetTester tester) async {
      final _FakeGgufDiscoveryCache cache = _FakeGgufDiscoveryCache(
        entry: GgufDiscoveryCacheEntry(
          result: _cachedVerifiedCandidateResult(),
          discoveredAtUtc: DateTime.utc(2026, 8, 27, 5, 2),
        ),
      );
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: _noSeeds,
        source: HuggingFaceDiscoveryService(
          fetchJson: (Uri uri) async => <Object?>[],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: GgufDiscoveryScreen(
            discoveryService: service,
            discoveryCache: cache,
            downloadService: _FakeModelDownloadService(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0 downloadable Candidates found'), findsOneWidget);
      expect(
        find.text(kModelCatalog.first.fileName),
        findsNothing,
      );
      expect(find.text('Download'), findsNothing);
    });

    testWidgets('hides review, rejection, and repository source errors',
        (WidgetTester tester) async {
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: _noSeeds,
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
          home: GgufDiscoveryScreen(
            discoveryService: service,
            discoveryCache: _FakeGgufDiscoveryCache(),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('discover-gguf-button')));
      await tester.pumpAndSettle();

      expect(find.text('0 downloadable Candidates found'), findsOneWidget);
      expect(
        find.text(
          'No downloadable Candidates were found in this discovery run.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('discovery-incomplete-warning')),
        findsOneWidget,
      );
      expect(
        find.text('Some repositories could not be checked: 1'),
        findsOneWidget,
      );
      expect(find.text('Publisher/Unknown-1B-Instruct-GGUF'), findsNothing);
      expect(find.text('Qwen/Qwen3.5-2B-Instruct-GGUF'), findsNothing);
      expect(find.text('Broken/Unavailable-Instruct-GGUF'), findsNothing);
      expect(find.text('Repository metadata unavailable.'), findsNothing);
      expect(find.textContaining('Needs review'), findsNothing);
      expect(find.textContaining('Rejected'), findsNothing);
      expect(find.textContaining('Source errors'), findsNothing);
    });

    testWidgets('shows a search failure without inventing model results',
        (WidgetTester tester) async {
      final GgufDiscoveryService service = GgufDiscoveryService(
        loadSeedRepositories: _noSeeds,
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
          home: GgufDiscoveryScreen(
            discoveryService: service,
            discoveryCache: _FakeGgufDiscoveryCache(),
          ),
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
    loadSeedRepositories: _noSeeds,
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

Future<List<String>> _noSeeds() async => const <String>[];

GgufDiscoveryResult _cachedCandidateResult() {
  return GgufDiscoveryResult(
    assessments: <GgufCandidateAssessment>[
      GgufCandidateAssessment(
        repositoryId: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
        disposition: GgufCandidateDisposition.candidate,
        reasons: const <String>[],
        warnings: const <String>[],
        artifact: GgufCandidateArtifact(
          repositoryId: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
          commitSha: '0123456789abcdef0123456789abcdef01234567',
          fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
          sizeBytes: 1000000000,
          sha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          downloadUri: Uri.parse(
            'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/'
            'resolve/0123456789abcdef0123456789abcdef01234567/'
            'qwen2.5-1.5b-instruct-q4_k_m.gguf',
          ),
          sourcePage: Uri.parse(
            'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF',
          ),
          license: 'Apache-2.0',
          licenseSourceRepository: 'Qwen/Qwen2.5-1.5B-Instruct-GGUF',
          hasCustomLicense: false,
          modelFamily: 'Qwen/ChatML',
          promptFormat: PromptFormat.chatml,
        ),
      ),
    ],
    sourceFailures: const <GgufDiscoverySourceFailure>[],
  );
}

GgufDiscoveryResult _cachedCustomLicenseResult() {
  return GgufDiscoveryResult(
    assessments: <GgufCandidateAssessment>[
      GgufCandidateAssessment(
        repositoryId: 'bartowski/google_gemma-3-1b-it-GGUF',
        disposition: GgufCandidateDisposition.candidate,
        reasons: const <String>[],
        warnings: const <String>[
          'Custom license — review gemma terms before download.',
        ],
        artifact: GgufCandidateArtifact(
          repositoryId: 'bartowski/google_gemma-3-1b-it-GGUF',
          commitSha: '0123456789abcdef0123456789abcdef01234567',
          fileName: 'google_gemma-3-1b-it-Q4_K_M.gguf',
          sizeBytes: 806000000,
          sha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          downloadUri: Uri.parse(
            'https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF/'
            'resolve/0123456789abcdef0123456789abcdef01234567/'
            'google_gemma-3-1b-it-Q4_K_M.gguf',
          ),
          sourcePage: Uri.parse(
            'https://huggingface.co/bartowski/google_gemma-3-1b-it-GGUF',
          ),
          license: 'gemma',
          licenseSourceRepository: 'bartowski/google_gemma-3-1b-it-GGUF',
          hasCustomLicense: true,
          modelFamily: 'Gemma',
          promptFormat: PromptFormat.gemma,
        ),
      ),
    ],
    sourceFailures: const <GgufDiscoverySourceFailure>[],
  );
}

GgufDiscoveryResult _cachedVerifiedCandidateResult() {
  final CatalogModel model = kModelCatalog.first;
  final Uri downloadUri = model.uri;
  final int resolveIndex = downloadUri.pathSegments.indexOf('resolve');
  final String commitSha = downloadUri.pathSegments[resolveIndex + 1];
  final String repositoryId = Uri.parse(model.sourcePage)
      .pathSegments
      .where((String segment) => segment.isNotEmpty)
      .join('/');
  return GgufDiscoveryResult(
    assessments: <GgufCandidateAssessment>[
      GgufCandidateAssessment(
        repositoryId: repositoryId,
        disposition: GgufCandidateDisposition.candidate,
        reasons: const <String>[],
        warnings: const <String>[],
        artifact: GgufCandidateArtifact(
          repositoryId: repositoryId,
          commitSha: commitSha,
          fileName: model.fileName,
          sizeBytes: model.sizeBytes,
          sha256: model.sha256,
          downloadUri: downloadUri,
          sourcePage: Uri.parse(model.sourcePage),
          license: model.license,
          licenseSourceRepository: repositoryId,
          hasCustomLicense: false,
          modelFamily: 'Qwen/ChatML',
          promptFormat: PromptFormat.chatml,
        ),
      ),
    ],
    sourceFailures: const <GgufDiscoverySourceFailure>[],
  );
}

class _FakeGgufDiscoveryCache implements GgufDiscoveryCache {
  _FakeGgufDiscoveryCache({this.entry});

  GgufDiscoveryCacheEntry? entry;
  int loadCalls = 0;
  int saveCalls = 0;

  @override
  Future<GgufDiscoveryCacheEntry?> load() async {
    loadCalls++;
    return entry;
  }

  @override
  Future<bool> save(
    GgufDiscoveryResult result, {
    required DateTime discoveredAtUtc,
  }) async {
    saveCalls++;
    entry = GgufDiscoveryCacheEntry(
      result: result,
      discoveredAtUtc: discoveredAtUtc,
    );
    return true;
  }
}

class _FakeModelDownloadService extends ModelDownloadService {
  _FakeModelDownloadService({
    this.status = InstalledArtifactStatus.absent,
    this.partial = 0,
    this.outcome = DownloadOutcome.completed,
  });

  InstalledArtifactStatus status;
  int partial;
  final DownloadOutcome outcome;
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
    if (outcome == DownloadOutcome.completed) {
      status = InstalledArtifactStatus.matchesExpected;
      partial = 0;
    }
    return DownloadResult(outcome);
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
