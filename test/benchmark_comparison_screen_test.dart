import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/screens/benchmark_comparison_screen.dart';
import 'package:local_ai_summarizer/theme/app_theme.dart';

void main() {
  testWidgets(
    'comparison cards use concise names and retain changed identities',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final Map<int, Map<String, Object?>> sessions =
          <int, Map<String, Object?>>{
            1: _session(
              completedAt: '2026-08-30T11:00:00.000Z',
              nanoName: 'Gemini Nano (AICore 0.release.prod_aicore_20260701)',
              qwenRate: 11,
            ),
            2: _session(
              completedAt: '2026-08-30T13:00:00.000Z',
              nanoName: 'Gemini Nano (AICore 0.release.prod_aicore_20260723)',
              qwenRate: 14,
            ),
          };

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: BenchmarkComparisonScreen(
              sessionIdA: 1,
              sessionIdB: 2,
              sessionLoader: (int id) async => sessions[id],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gemini Nano'), findsOneWidget);
      expect(find.text('AICore'), findsOneWidget);
      expect(find.text('Qwen2.5 1.5B Instruct'), findsOneWidget);
      expect(find.text('GGUF'), findsOneWidget);
      expect(find.text('qwen2.5-1.5b-instruct-q4_k_m.gguf'), findsNothing);
      expect(
        find.text('Recorded identity changed between sessions'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Older identity: Gemini Nano (AICore '
          '0.release.prod_aicore_20260701)',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Newer identity: Gemini Nano (AICore '
          '0.release.prod_aicore_20260723)',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Map<String, Object?> _session({
  required String completedAt,
  required String nanoName,
  required int qwenRate,
}) {
  return <String, Object?>{
    'completed_at': completedAt,
    'passage': 'The same controlled passage.',
    'instruction': 'Extract the expected facts.',
    'runs_per_model': 1,
    'runs': <Map<String, Object?>>[
      _run(
        modelOrder: 0,
        modelId: 'system_gemini_nano',
        modelName: nanoName,
        modelPath: 'system://aicore/nano',
        engineType: 'nano',
        promptFormat: 'plain',
        latency: 0.7,
        tokenCount: 40,
      ),
      _run(
        modelOrder: 1,
        modelId: '/models/qwen2.5-1.5b-instruct-q4_k_m.gguf',
        modelName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
        modelPath: '/models/qwen2.5-1.5b-instruct-q4_k_m.gguf',
        engineType: 'gguf',
        promptFormat: 'chatml',
        latency: 40 / qwenRate,
        tokenCount: 40,
      ),
    ],
  };
}

Map<String, Object?> _run({
  required int modelOrder,
  required String modelId,
  required String modelName,
  required String modelPath,
  required String engineType,
  required String promptFormat,
  required double latency,
  required int tokenCount,
}) {
  return <String, Object?>{
    'model_order': modelOrder,
    'run_number': 1,
    'model_id': modelId,
    'model_name': modelName,
    'model_path': modelPath,
    'engine_type': engineType,
    'prompt_format': promptFormat,
    'ttft_seconds': engineType == 'nano' ? null : 0.4,
    'latency_seconds': latency,
    'token_count': tokenCount,
    'output_text': 'A representative output.',
    'error_message': null,
    'recall_found': 8,
    'recall_total': 10,
    'missed_fact_ids': null,
    'expected_sentence_count': null,
    'actual_sentence_count': null,
  };
}
