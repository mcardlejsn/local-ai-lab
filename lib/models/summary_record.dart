class SummaryRecord {
  final int? id;
  final String originalText;
  final String generatedSummary;
  final String taskType;
  final DateTime createdAt;
  final double? latencySeconds;
  final double? ttftSeconds;
  final double? tokensPerSecond;

  SummaryRecord({
    this.id,
    required this.originalText,
    required this.generatedSummary,
    required this.taskType,
    required this.createdAt,
    this.latencySeconds,
    this.ttftSeconds,
    this.tokensPerSecond,
  });

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
    );
  }
}