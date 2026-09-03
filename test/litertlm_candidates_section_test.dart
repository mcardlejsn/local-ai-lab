import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/litertlm_model_artifact.dart';
import 'package:local_ai_summarizer/services/model_download_service.dart';
import 'package:local_ai_summarizer/widgets/litertlm_candidates_section.dart';

void main() {
  testWidgets('shows the two curated exact artifacts and context metadata', (
    WidgetTester tester,
  ) async {
    await _pumpCatalog(tester, downloadService: _FakeDownloadService());

    expect(find.text('Curated LiteRT-LM'), findsOneWidget);
    expect(find.text('Qwen3 0.6B'), findsOneWidget);
    expect(find.text('OLMo 2 1B Instruct'), findsOneWidget);
    expect(find.text('LiteRT-LM'), findsNWidgets(2));
    expect(
      find.text('Artifact context: 4,096 tokens · app runtime: 2,048 tokens'),
      findsOneWidget,
    );
    expect(find.text('Context: 4,096 tokens'), findsOneWidget);
    expect(find.text('GGUF Discovery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps an installed curated artifact visible', (
    WidgetTester tester,
  ) async {
    await _pumpCatalog(
      tester,
      downloadService: _FakeDownloadService(),
      installedArtifactIds: <String>{prototypeLiteRtLmArtifact.identity},
    );

    expect(
      find.byKey(
        ValueKey<String>(
          'litertlm-installed-${prototypeLiteRtLmArtifact.filename}',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey<String>(
          'litertlm-download-${olmo2OneBInstructLiteRtLmArtifact.filename}',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('reports a same-name unrecognized file as a conflict', (
    WidgetTester tester,
  ) async {
    final _FakeDownloadService service = _FakeDownloadService(
      existingFiles: <String>{prototypeLiteRtLmArtifact.filename},
    );

    await _pumpCatalog(tester, downloadService: service);

    expect(
      find.textContaining('different or unrecognized file'),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey<String>(
          'litertlm-download-${prototypeLiteRtLmArtifact.filename}',
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('confirms and installs the exact selected artifact', (
    WidgetTester tester,
  ) async {
    final _FakeDownloadService service = _FakeDownloadService();
    int scanCalls = 0;

    await _pumpCatalog(
      tester,
      downloadService: service,
      onModelInstalled: () async {
        scanCalls++;
      },
    );

    await tester.tap(
      find.byKey(
        ValueKey<String>(
          'litertlm-download-${prototypeLiteRtLmArtifact.filename}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Download LiteRT-LM Candidate?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-litertlm-download')));
    await tester.pumpAndSettle();

    expect(service.downloadCalls, 1);
    expect(service.lastUrl, Uri.parse(prototypeLiteRtLmArtifact.downloadUrl));
    expect(service.lastFileName, prototypeLiteRtLmArtifact.filename);
    expect(service.lastSha256, prototypeLiteRtLmArtifact.sha256);
    expect(scanCalls, 1);
    expect(
      find.byKey(
        ValueKey<String>(
          'litertlm-installed-${prototypeLiteRtLmArtifact.filename}',
        ),
      ),
      findsOneWidget,
    );
  });
}

Future<void> _pumpCatalog(
  WidgetTester tester, {
  required _FakeDownloadService downloadService,
  Set<String> installedArtifactIds = const <String>{},
  Future<void> Function()? onModelInstalled,
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.dark,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: LiteRtLmCandidatesSection(
            installedArtifactIds: installedArtifactIds,
            installedInventoryLoading: false,
            downloadService: downloadService,
            onModelInstalled: onModelInstalled,
            externalUriLauncher: (_) async => true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeDownloadService extends ModelDownloadService {
  _FakeDownloadService({Set<String>? existingFiles})
    : existingFiles = existingFiles ?? <String>{};

  final Set<String> existingFiles;
  final Map<String, int> partials = <String, int>{};
  int downloadCalls = 0;
  Uri? lastUrl;
  String? lastFileName;
  String? lastSha256;

  @override
  Future<InstalledArtifactSizeStatus> installedArtifactSizeStatus({
    required String fileName,
    required int expectedSizeBytes,
  }) async {
    return existingFiles.contains(fileName)
        ? InstalledArtifactSizeStatus.matchesExpectedSize
        : InstalledArtifactSizeStatus.absent;
  }

  @override
  Future<int> partialBytes(String fileName) async {
    return partials[fileName] ?? 0;
  }

  @override
  Future<void> discardPartial(String fileName) async {
    partials.remove(fileName);
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
    lastUrl = url;
    lastFileName = fileName;
    lastSha256 = expectedSha256;
    onProgress?.call(
      DownloadProgress(
        receivedBytes: prototypeLiteRtLmArtifact.sizeBytes,
        totalBytes: prototypeLiteRtLmArtifact.sizeBytes,
      ),
    );
    return DownloadResult(
      DownloadOutcome.completed,
      filePath: '/models/$fileName',
    );
  }
}
