import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/model_recommendation.dart';

void main() {
  test('separates Recall and length from performance recommendations', () {
    final ModelRecommendationSnapshot? snapshot =
        buildModelRecommendationSnapshot(
          _session(
            taskType: '2-Sentence Summary',
            runs: <Map<String, Object?>>[
              ..._runs(
                modelOrder: 0,
                modelId: 'quality',
                modelName: 'Quality model',
                latency: 2,
                ttft: 0.4,
                tokenCount: 20,
                recall: 9,
                actualSentences: const <int>[2, 2, 2],
              ),
              ..._runs(
                modelOrder: 1,
                modelId: 'fast',
                modelName: 'Fast model',
                latency: 1,
                ttft: 0.2,
                tokenCount: 30,
                recall: 8,
                actualSentences: const <int>[2, 3, 2],
              ),
            ],
          ),
        );

    expect(snapshot, isNotNull);
    expect(snapshot!.taskLabel, '2-Sentence Summary');
    expect(snapshot.comparedModelCount, 2);

    final RecommendedModel quality = snapshot.models.singleWhere(
      (RecommendedModel model) => model.modelId == 'quality',
    );
    expect(
      quality.strengths.map((strength) => strength.metric),
      containsAll(<ModelRecommendationMetric>[
        ModelRecommendationMetric.recall,
        ModelRecommendationMetric.lengthCompliance,
      ]),
    );
    expect(
      quality.strengths.map((strength) => strength.metric),
      isNot(contains(ModelRecommendationMetric.latency)),
    );

    final RecommendedModel fast = snapshot.models.singleWhere(
      (RecommendedModel model) => model.modelId == 'fast',
    );
    expect(
      fast.strengths.map((strength) => strength.metric),
      containsAll(<ModelRecommendationMetric>[
        ModelRecommendationMetric.latency,
        ModelRecommendationMetric.ttft,
        ModelRecommendationMetric.generationSpeed,
      ]),
    );
  });

  test('recognizes ties without creating an overall score', () {
    final ModelRecommendationSnapshot snapshot =
        buildModelRecommendationSnapshot(
          _session(
            runs: <Map<String, Object?>>[
              ..._runs(
                modelOrder: 0,
                modelId: 'a',
                modelName: 'Model A',
                latency: 1,
                ttft: 0.2,
                tokenCount: 20,
                recall: 7,
              ),
              ..._runs(
                modelOrder: 1,
                modelId: 'b',
                modelName: 'Model B',
                latency: 1,
                ttft: 0.2,
                tokenCount: 20,
                recall: 7,
              ),
            ],
          ),
        )!;

    expect(snapshot.models, hasLength(2));
    for (final RecommendedModel model in snapshot.models) {
      expect(
        model.strengths.map((strength) => strength.metric),
        containsAll(
          ModelRecommendationMetric.values.where(
            (ModelRecommendationMetric metric) =>
                metric != ModelRecommendationMetric.lengthCompliance,
          ),
        ),
      );
    }
  });

  test('requires two models with successful runs', () {
    final Map<String, Object?> session = _session(
      runs: <Map<String, Object?>>[
        ..._runs(
          modelOrder: 0,
          modelId: 'success',
          modelName: 'Successful model',
          latency: 1,
          ttft: 0.2,
          tokenCount: 20,
          recall: 7,
        ),
        ..._runs(
          modelOrder: 1,
          modelId: 'failed',
          modelName: 'Failed model',
          latency: 1,
          ttft: null,
          tokenCount: 0,
          recall: null,
          error: 'Runtime failed.',
        ),
      ],
    );

    expect(buildModelRecommendationSnapshot(session), isNull);
  });

  test('ignores legacy Nano latency values stored as TTFT', () {
    final ModelRecommendationSnapshot snapshot =
        buildModelRecommendationSnapshot(
          _session(
            runs: <Map<String, Object?>>[
              ..._runs(
                modelOrder: 0,
                modelId: 'nano',
                modelName: 'Gemini Nano',
                engineType: 'nano',
                latency: 0.7,
                ttft: 0.7,
                tokenCount: 40,
                recall: 8,
              ),
              ..._runs(
                modelOrder: 1,
                modelId: 'gguf',
                modelName: 'GGUF model',
                latency: 1.2,
                ttft: 0.3,
                tokenCount: 40,
                recall: 8,
              ),
            ],
          ),
        )!;

    final RecommendedModel nano = snapshot.models.singleWhere(
      (RecommendedModel model) => model.modelId == 'nano',
    );
    expect(
      nano.strengths.map((strength) => strength.metric),
      isNot(contains(ModelRecommendationMetric.ttft)),
    );
    final RecommendedModel gguf = snapshot.models.singleWhere(
      (RecommendedModel model) => model.modelId == 'gguf',
    );
    expect(
      gguf.strengths.map((strength) => strength.metric),
      contains(ModelRecommendationMetric.ttft),
    );
  });
}

Map<String, Object?> _session({
  String? taskType,
  required List<Map<String, Object?>> runs,
}) {
  return <String, Object?>{
    'id': 42,
    'completed_at': '2026-08-30T12:00:00.000Z',
    'task_type': taskType,
    'runs_per_model': 3,
    'runs': runs,
  };
}

List<Map<String, Object?>> _runs({
  required int modelOrder,
  required String modelId,
  required String modelName,
  required double latency,
  required double? ttft,
  required int tokenCount,
  required int? recall,
  String engineType = 'gguf',
  List<int>? actualSentences,
  String? error,
}) {
  return List<Map<String, Object?>>.generate(3, (int index) {
    return <String, Object?>{
      'id': modelOrder * 10 + index,
      'model_order': modelOrder,
      'run_number': index + 1,
      'model_id': modelId,
      'model_name': modelName,
      'model_path': '/models/$modelId.gguf',
      'engine_type': engineType,
      'prompt_format': engineType == 'nano' ? 'plain' : 'chatml',
      'ttft_seconds': ttft,
      'latency_seconds': latency,
      'token_count': tokenCount,
      'output_text': error == null ? 'Successful output.' : '',
      'error_message': error,
      'recall_found': recall,
      'recall_total': recall == null ? null : 10,
      'missed_fact_ids': null,
      'expected_sentence_count': actualSentences == null ? null : 2,
      'actual_sentence_count': actualSentences?[index],
    };
  });
}
