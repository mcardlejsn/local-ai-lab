import 'package:flutter/foundation.dart';

import 'recall_checklist.dart';

enum BenchmarkTestCaseSource { controlled, playground, restored }

@immutable
class BenchmarkTestCase {
  const BenchmarkTestCase({
    required this.passage,
    required this.instruction,
    required this.source,
    this.taskType,
  });

  factory BenchmarkTestCase.controlled() => BenchmarkTestCase(
    passage: defaultBenchmarkPassage,
    instruction: defaultBenchmarkInstruction,
    source: BenchmarkTestCaseSource.controlled,
  );

  final String passage;
  final String instruction;
  final BenchmarkTestCaseSource source;

  /// Playground preset name when this case was transferred from Playground.
  /// Kept as structured metadata so later evaluation never has to infer the
  /// task from arbitrary instruction text.
  final String? taskType;

  bool get isFromPlayground => source == BenchmarkTestCaseSource.playground;

  String get sourceLabel => switch (source) {
    BenchmarkTestCaseSource.controlled => 'Controlled test',
    BenchmarkTestCaseSource.playground => 'From Playground',
    BenchmarkTestCaseSource.restored => 'Latest saved benchmark',
  };
}
