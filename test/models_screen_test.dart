import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/screens/model_download_screen.dart';
import 'package:local_ai_summarizer/services/model_download_service.dart';
import 'package:local_ai_summarizer/services/model_manager_service.dart';
import 'package:local_ai_summarizer/theme/app_theme.dart';

void main() {
  testWidgets('Models sections stay distinct at the device text scale', (
    WidgetTester tester,
  ) async {
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
          downloadService: _OfflineModelDownloadService(),
          candidateBuilder: (_) => const Center(
            child: Text(
              'Candidate discovery content',
              key: Key('candidate-test-content'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Manage local inference models'), findsOneWidget);
    expect(find.byKey(const Key('installed-models-summary')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Verified'));
    await tester.pump();
    expect(find.text('Verified models'), findsOneWidget);
    expect(find.text('Network use'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Candidates'));
    await tester.pump();
    expect(find.byKey(const Key('candidate-test-content')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _OfflineModelDownloadService extends ModelDownloadService {
  @override
  Future<bool> isInstalled(String fileName) async => false;

  @override
  Future<int> partialBytes(String fileName) async => 0;
}
