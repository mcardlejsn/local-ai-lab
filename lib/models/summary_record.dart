class SummaryRecord {
  final int? id;
  final String originalText;
  final String generatedSummary;
  final String taskType;
  final DateTime createdAt;

  SummaryRecord({
    this.id,
    required this.originalText,
    required this.generatedSummary,
    required this.taskType,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'original_text': originalText,
      'generated_summary': generatedSummary,
      'task_type': taskType,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SummaryRecord.fromMap(Map<String, dynamic> map) {
    return SummaryRecord(
      id: map['id'] as int?,
      originalText: map['original_text'] as String,
      generatedSummary: map['generated_summary'] as String,
      taskType: map['task_type'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}