import '../services/model_manager_service.dart';
import 'benchmark_session.dart';

enum ModelRecommendationMetric {
  recall,
  lengthCompliance,
  latency,
  ttft,
  generationSpeed,
}

extension ModelRecommendationMetricLabel on ModelRecommendationMetric {
  String get label => switch (this) {
    ModelRecommendationMetric.recall => 'Best Recall',
    ModelRecommendationMetric.lengthCompliance => 'Best length compliance',
    ModelRecommendationMetric.latency => 'Lowest latency',
    ModelRecommendationMetric.ttft => 'Lowest TTFT',
    ModelRecommendationMetric.generationSpeed => 'Highest estimated rate',
  };
}

class ModelRecommendationStrength {
  const ModelRecommendationStrength({
    required this.metric,
    required this.valueLabel,
  });

  final ModelRecommendationMetric metric;
  final String valueLabel;
}

class RecommendedModel {
  const RecommendedModel({
    required this.modelId,
    required this.modelName,
    required this.modelPath,
    required this.engine,
    required this.strengths,
  });

  final String modelId;
  final String modelName;
  final String modelPath;
  final ModelEngine engine;
  final List<ModelRecommendationStrength> strengths;
}

class ModelRecommendationSnapshot {
  const ModelRecommendationSnapshot({
    required this.sessionId,
    required this.completedAt,
    required this.taskLabel,
    required this.runsPerModel,
    required this.comparedModelCount,
    required this.models,
  });

  final int sessionId;
  final DateTime completedAt;
  final String taskLabel;
  final int runsPerModel;
  final int comparedModelCount;
  final List<RecommendedModel> models;
}

/// Derives relative strengths from one saved Benchmark session.
///
/// Every winner is calculated only against models that were run together in
/// this session. No threshold, overall score, or cross-session comparison is
/// introduced. Null means the saved data does not contain at least two models
/// with successful runs.
ModelRecommendationSnapshot? buildModelRecommendationSnapshot(
  Map<String, Object?> session,
) {
  final Object? rawRuns = session['runs'];
  if (rawRuns is! List) return null;

  final List<Map<String, Object?>> runMaps;
  try {
    runMaps = rawRuns.cast<Map<String, Object?>>();
  } on TypeError {
    return null;
  }

  final List<BenchmarkAggregate> successful = buildAggregatesFromSavedRuns(
    runMaps,
  ).where((BenchmarkAggregate aggregate) => aggregate.hasAnySuccess).toList();
  if (successful.length < 2) return null;

  final Map<String, List<ModelRecommendationStrength>> strengths =
      <String, List<ModelRecommendationStrength>>{
        for (final BenchmarkAggregate aggregate in successful)
          aggregate.modelId: <ModelRecommendationStrength>[],
      };

  _addHighestWinners(
    successful,
    valueOf: (BenchmarkAggregate aggregate) => aggregate.medianRecallFound,
    strengthFor: (BenchmarkAggregate aggregate) => ModelRecommendationStrength(
      metric: ModelRecommendationMetric.recall,
      valueLabel: aggregate.recallTotal == null
          ? _formatNumber(aggregate.medianRecallFound!)
          : '${_formatNumber(aggregate.medianRecallFound!)}/'
                '${aggregate.recallTotal}',
    ),
    strengths: strengths,
  );

  _addHighestWinners(
    successful,
    valueOf: (BenchmarkAggregate aggregate) {
      final int evaluated = aggregate.sentenceCountRuns.length;
      if (evaluated == 0) return null;
      return aggregate.sentenceCountMetRunCount / evaluated;
    },
    strengthFor: (BenchmarkAggregate aggregate) => ModelRecommendationStrength(
      metric: ModelRecommendationMetric.lengthCompliance,
      valueLabel:
          '${aggregate.sentenceCountMetRunCount}/'
          '${aggregate.sentenceCountRuns.length} runs met',
    ),
    strengths: strengths,
  );

  _addLowestWinners(
    successful,
    valueOf: (BenchmarkAggregate aggregate) => aggregate.medianLatencySeconds,
    strengthFor: (BenchmarkAggregate aggregate) => ModelRecommendationStrength(
      metric: ModelRecommendationMetric.latency,
      valueLabel: '${aggregate.medianLatencySeconds!.toStringAsFixed(2)}s',
    ),
    strengths: strengths,
  );

  _addLowestWinners(
    successful,
    valueOf: (BenchmarkAggregate aggregate) => aggregate.medianTtftSeconds,
    strengthFor: (BenchmarkAggregate aggregate) => ModelRecommendationStrength(
      metric: ModelRecommendationMetric.ttft,
      valueLabel: '${aggregate.medianTtftSeconds!.toStringAsFixed(2)}s',
    ),
    strengths: strengths,
  );

  _addHighestWinners(
    successful,
    valueOf: (BenchmarkAggregate aggregate) => aggregate.medianTokensPerSecond,
    strengthFor: (BenchmarkAggregate aggregate) => ModelRecommendationStrength(
      metric: ModelRecommendationMetric.generationSpeed,
      valueLabel:
          '${aggregate.medianTokensPerSecond!.toStringAsFixed(1)} est. tok/s',
    ),
    strengths: strengths,
  );

  final List<RecommendedModel> models = successful
      .where(
        (BenchmarkAggregate aggregate) =>
            strengths[aggregate.modelId]!.isNotEmpty,
      )
      .map(
        (BenchmarkAggregate aggregate) => RecommendedModel(
          modelId: aggregate.modelId,
          modelName: aggregate.modelName,
          modelPath: aggregate.modelPath,
          engine: aggregate.engine,
          strengths: List<ModelRecommendationStrength>.unmodifiable(
            strengths[aggregate.modelId]!,
          ),
        ),
      )
      .toList(growable: false);

  final DateTime? completedAt = DateTime.tryParse(
    session['completed_at']?.toString() ?? '',
  );
  final String? taskType = _nonEmptyString(session['task_type']);

  return ModelRecommendationSnapshot(
    sessionId: session['id'] as int,
    completedAt: (completedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
        .toUtc(),
    taskLabel: taskType ?? 'Controlled extraction',
    runsPerModel: session['runs_per_model'] as int,
    comparedModelCount: successful.length,
    models: List<RecommendedModel>.unmodifiable(models),
  );
}

void _addHighestWinners(
  List<BenchmarkAggregate> aggregates, {
  required double? Function(BenchmarkAggregate aggregate) valueOf,
  required ModelRecommendationStrength Function(BenchmarkAggregate aggregate)
  strengthFor,
  required Map<String, List<ModelRecommendationStrength>> strengths,
}) {
  _addWinners(
    aggregates,
    valueOf: valueOf,
    strengthFor: strengthFor,
    strengths: strengths,
    prefer: (double candidate, double current) => candidate > current,
  );
}

void _addLowestWinners(
  List<BenchmarkAggregate> aggregates, {
  required double? Function(BenchmarkAggregate aggregate) valueOf,
  required ModelRecommendationStrength Function(BenchmarkAggregate aggregate)
  strengthFor,
  required Map<String, List<ModelRecommendationStrength>> strengths,
}) {
  _addWinners(
    aggregates,
    valueOf: valueOf,
    strengthFor: strengthFor,
    strengths: strengths,
    prefer: (double candidate, double current) => candidate < current,
  );
}

void _addWinners(
  List<BenchmarkAggregate> aggregates, {
  required double? Function(BenchmarkAggregate aggregate) valueOf,
  required ModelRecommendationStrength Function(BenchmarkAggregate aggregate)
  strengthFor,
  required Map<String, List<ModelRecommendationStrength>> strengths,
  required bool Function(double candidate, double current) prefer,
}) {
  final List<(BenchmarkAggregate, double)> measured = aggregates
      .map((BenchmarkAggregate aggregate) => (aggregate, valueOf(aggregate)))
      .where((record) => record.$2 != null)
      .map((record) => (record.$1, record.$2!))
      .toList(growable: false);
  if (measured.isEmpty) return;

  double winningValue = measured.first.$2;
  for (final record in measured.skip(1)) {
    if (prefer(record.$2, winningValue)) winningValue = record.$2;
  }

  for (final record in measured) {
    if (record.$2 == winningValue) {
      strengths[record.$1.modelId]!.add(strengthFor(record.$1));
    }
  }
}

String _formatNumber(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
