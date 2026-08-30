import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/sentence_count_evaluation.dart';
import 'package:local_ai_summarizer/models/summary_record.dart';

void main() {
  group('sentence count evaluation', () {
    test('evaluates only the structured two-sentence task', () {
      final SentenceCountEvaluation? evaluation = evaluateSentenceCount(
        output: 'The build passed. The release is ready.',
        taskType: twoSentenceSummaryTask,
      );

      expect(evaluation?.expected, 2);
      expect(evaluation?.actual, 2);
      expect(evaluation?.met, isTrue);
      expect(
        evaluateSentenceCount(
          output: 'The build passed. The release is ready.',
          taskType: 'Custom',
        ),
        isNull,
      );
    });

    test('reports too few and too many sentences', () {
      expect(
        evaluateSentenceCount(
          output: 'Only one sentence.',
          taskType: twoSentenceSummaryTask,
        )?.met,
        isFalse,
      );
      expect(
        evaluateSentenceCount(
          output: 'One. Two. Three.',
          taskType: twoSentenceSummaryTask,
        )?.actual,
        3,
      );
    });

    test('does not split decimals or common abbreviations', () {
      expect(countSentences('Version 4.2 shipped. Error fell to 1.5%.'), 2);
      expect(countSentences('Dr. Chen approved it. Release followed.'), 2);
      expect(countSentences('The U.S. economy grew. Markets rallied.'), 2);
    });

    test('handles grouped punctuation and an unpunctuated final sentence', () {
      expect(countSentences('It paused... Then continued.'), 2);
      expect(countSentences('First sentence. Second sentence'), 2);
      expect(countSentences('   '), 0);
    });
  });

  group('saved Playground sentence count', () {
    test('round-trips nullable evaluation fields', () {
      final SummaryRecord record = SummaryRecord(
        originalText: 'Input',
        generatedSummary: 'One. Two.',
        taskType: twoSentenceSummaryTask,
        createdAt: DateTime.utc(2026, 8, 30),
        expectedSentenceCount: 2,
        actualSentenceCount: 2,
      );

      final SummaryRecord restored = SummaryRecord.fromMap(record.toMap());
      expect(restored.expectedSentenceCount, 2);
      expect(restored.actualSentenceCount, 2);
      expect(restored.sentenceCountMet, isTrue);
    });

    test('older records remain unevaluated', () {
      final SummaryRecord restored = SummaryRecord.fromMap(<String, dynamic>{
        'id': 1,
        'original_text': 'Input',
        'generated_summary': 'Older output.',
        'task_type': twoSentenceSummaryTask,
        'created_at': DateTime.utc(2026, 8, 29).toIso8601String(),
      });

      expect(restored.sentenceCountMet, isNull);
    });
  });
}
