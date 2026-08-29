import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/screens/results_screen.dart';
import 'package:local_ai_summarizer/theme/app_theme.dart';

void main() {
  testWidgets('Results keeps Playground and Benchmark archives distinct', (
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
        home: ResultsScreen(
          playgroundRunsBuilder: (_) => const Center(
            child: Text(
              'Playground archive content',
              key: Key('playground-archive-test-content'),
            ),
          ),
          benchmarksBuilder: (_) => const Center(
            child: Text(
              'Benchmark archive content',
              key: Key('benchmark-archive-test-content'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Saved runs and benchmarks'), findsOneWidget);
    expect(
      find.byKey(const Key('playground-archive-test-content')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Benchmarks'));
    await tester.pump();
    expect(
      find.byKey(const Key('benchmark-archive-test-content')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
