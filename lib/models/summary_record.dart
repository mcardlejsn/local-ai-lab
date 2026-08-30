class SummaryRecord {
  final int? id;
  final String originalText;
  final String generatedSummary;
  final String taskType;
  final DateTime createdAt;
  final double? latencySeconds;
  final double? ttftSeconds;
  final double? tokensPerSecond;
  final String? engineType;
  final String? modelName;
  final int? tokenCount;
  final int? expectedSentenceCount;
  final int? actualSentenceCount;

  SummaryRecord({
    this.id,
    required this.originalText,
    required this.generatedSummary,
    required this.taskType,
    required this.createdAt,
    this.latencySeconds,
    this.ttftSeconds,
    this.tokensPerSecond,
    this.engineType,
    this.modelName,
    this.tokenCount,
    this.expectedSentenceCount,
    this.actualSentenceCount,
  });

  bool? get sentenceCountMet {
    if (expectedSentenceCount == null || actualSentenceCount == null) {
      return null;
    }
    return actualSentenceCount == expectedSentenceCount;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'original_text': originalText,
      'generated_summary': generatedSummary,
      'task_type': taskType,
      'created_at': createdAt.toIso8601String(),
      'latency_seconds': latencySeconds,
      'ttft_seconds': ttftSeconds,
      'tokens_per_sec': tokensPerSecond,
      'engine_type': engineType,
      'model_name': modelName,
      'token_count': tokenCount,
      'expected_sentence_count': expectedSentenceCount,
      'actual_sentence_count': actualSentenceCount,
    };
  }

  factory SummaryRecord.fromMap(Map<String, dynamic> map) {
    return SummaryRecord(
      id: map['id'] as int?,
      originalText: map['original_text'] as String,
      generatedSummary: map['generated_summary'] as String,
      taskType: map['task_type'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      latencySeconds: (map['latency_seconds'] as num?)?.toDouble(),
      ttftSeconds: (map['ttft_seconds'] as num?)?.toDouble(),
      tokensPerSecond: (map['tokens_per_sec'] as num?)?.toDouble(),
      engineType: map['engine_type'] as String?,
      modelName: map['model_name'] as String?,
      tokenCount: map['token_count'] as int?,
      expectedSentenceCount: map['expected_sentence_count'] as int?,
      actualSentenceCount: map['actual_sentence_count'] as int?,
    );
  }
}
