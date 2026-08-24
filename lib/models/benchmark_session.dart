import '../services/model_manager_service.dart';

class BenchmarkModelResult {
  final String modelName;
  final ModelEngine engine;
  final double? ttftSeconds;
  final double totalLatencySeconds;
  final int tokenCount;
  final double tokensPerSecond;
  final String outputText;
  final String? errorMessage;

  /// Row id of the saved `benchmark_runs` record. Null for a run that is still
  /// live in memory and has not been written to a session yet, which is what
  /// makes a run scorable or not.
  final int? runId;

  /// Manual accuracy score for this run's output. Null means unscored.
  final int? accuracyScore;

  /// Optional free-text note recording why the score was given, e.g. what the
  /// model fabricated or dropped.
  final String? scoreNote;

  BenchmarkModelResult({
    required this.modelName,
    required this.engine,
    this.ttftSeconds,
    required this.totalLatencySeconds,
    required this.tokenCount,
    required this.tokensPerSecond,
    required this.outputText,
    this.errorMessage,
    this.runId,
    this.accuracyScore,
    this.scoreNote,
  });

  bool get isScorable => runId != null;

  bool get isScored => accuracyScore != null;

  /// Returns a copy with the score fields replaced outright. Both arguments are
  /// written as given, so passing null clears that field.
  BenchmarkModelResult copyWithScore(int? accuracyScore, String? scoreNote) {
    return BenchmarkModelResult(
      modelName: modelName,
      engine: engine,
      ttftSeconds: ttftSeconds,
      totalLatencySeconds: totalLatencySeconds,
      tokenCount: tokenCount,
      tokensPerSecond: tokensPerSecond,
      outputText: outputText,
      errorMessage: errorMessage,
      runId: runId,
      accuracyScore: accuracyScore,
      scoreNote: scoreNote,
    );
  }
}

class BenchmarkAggregate {
  final String modelId;
  final String modelName;
  final String modelPath;
  final ModelEngine engine;
  final PromptFormat promptFormat;
  final List<BenchmarkModelResult> runs = [];

  BenchmarkAggregate({
    required this.modelId,
    required this.modelName,
    required this.modelPath,
    required this.engine,
    required this.promptFormat,
  });

  List<BenchmarkModelResult> get successfulRuns =>
      runs.where((r) => r.errorMessage == null).toList();

  bool get hasAnySuccess => successfulRuns.isNotEmpty;

  String? get firstError {
    for (final r in runs) {
      if (r.errorMessage != null) return r.errorMessage;
    }
    return null;
  }

  static double? _median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final int mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  double? get medianTokensPerSecond =>
      _median(successfulRuns.map((r) => r.tokensPerSecond).toList());

  double? get medianTtftSeconds => _median(
        successfulRuns
            .where((r) => r.ttftSeconds != null)
            .map((r) => r.ttftSeconds!)
            .toList(),
      );

  double? get medianLatencySeconds =>
      _median(successfulRuns.map((r) => r.totalLatencySeconds).toList());

  double? get minLatencySeconds {
    final s = successfulRuns;
    if (s.isEmpty) return null;
    return s.map((r) => r.totalLatencySeconds).reduce((a, b) => a < b ? a : b);
  }

  double? get maxLatencySeconds {
    final s = successfulRuns;
    if (s.isEmpty) return null;
    return s.map((r) => r.totalLatencySeconds).reduce((a, b) => a > b ? a : b);
  }

  int? get medianTokenCount {
    final value =
        _median(successfulRuns.map((r) => r.tokenCount.toDouble()).toList());
    return value?.round();
  }

  List<BenchmarkModelResult> get scoredRuns =>
      successfulRuns.where((r) => r.isScored).toList();

  int get scoredRunCount => scoredRuns.length;

  double? get medianAccuracyScore => _median(
        scoredRuns.map((r) => r.accuracyScore!.toDouble()).toList(),
      );

  /// The run whose total latency sits at the median, used as the representative
  /// output so the displayed text corresponds to the displayed timings.
  BenchmarkModelResult? get medianRun {
    final s = successfulRuns;
    if (s.isEmpty) return null;
    final sorted = [...s]
      ..sort((a, b) => a.totalLatencySeconds.compareTo(b.totalLatencySeconds));
    return sorted[(sorted.length - 1) ~/ 2];
  }
}

/// Reconstructs the per-model aggregates from the saved `benchmark_runs` rows
/// of one session, in their saved model order. Shared by the live benchmark
/// screen's automatic restoration and the read-only archive.
List<BenchmarkAggregate> buildAggregatesFromSavedRuns(
  List<Map<String, Object?>> runMaps,
) {
  final aggregatesByOrder = <int, BenchmarkAggregate>{};

  for (final runMap in runMaps) {
    final modelOrder = runMap['model_order'] as int;
    final aggregate = aggregatesByOrder.putIfAbsent(
      modelOrder,
      () => BenchmarkAggregate(
        modelId: runMap['model_id'] as String,
        modelName: runMap['model_name'] as String,
        modelPath: runMap['model_path'] as String,
        engine: ModelEngine.values.byName(
          runMap['engine_type'] as String,
        ),
        promptFormat: PromptFormat.values.byName(
          runMap['prompt_format'] as String,
        ),
      ),
    );

    final latencySeconds = (runMap['latency_seconds'] as num).toDouble();
    final tokenCount = runMap['token_count'] as int;
    aggregate.runs.add(
      BenchmarkModelResult(
        modelName: runMap['model_name'] as String,
        engine: aggregate.engine,
        ttftSeconds: (runMap['ttft_seconds'] as num?)?.toDouble(),
        totalLatencySeconds: latencySeconds,
        tokenCount: tokenCount,
        tokensPerSecond: latencySeconds > 0 ? tokenCount / latencySeconds : 0,
        outputText: runMap['output_text'] as String,
        errorMessage: runMap['error_message'] as String?,
        runId: runMap['id'] as int?,
        accuracyScore: runMap['accuracy_score'] as int?,
        scoreNote: runMap['score_note'] as String?,
      ),
    );
  }

  final orderedEntries = aggregatesByOrder.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return orderedEntries.map((entry) => entry.value).toList();
}

String formatBenchmarkDateTime(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final year = value.year.toString();
  final minute = value.minute.toString().padLeft(2, '0');
  final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final period = value.hour < 12 ? 'AM' : 'PM';
  return '$month/$day/$year $hour12:$minute $period';
}