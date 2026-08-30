const String twoSentenceSummaryTask = '2-Sentence Summary';

class SentenceCountEvaluation {
  const SentenceCountEvaluation({required this.expected, required this.actual});

  final int expected;
  final int actual;

  bool get met => actual == expected;
}

int? expectedSentenceCountForTask(String? taskType) {
  return taskType == twoSentenceSummaryTask ? 2 : null;
}

SentenceCountEvaluation? evaluateSentenceCount({
  required String output,
  required String? taskType,
}) {
  final int? expected = expectedSentenceCountForTask(taskType);
  if (expected == null || output.trim().isEmpty) return null;
  return SentenceCountEvaluation(
    expected: expected,
    actual: countSentences(output),
  );
}

/// Counts prose sentences deterministically without interpreting the prompt.
///
/// A terminal punctuation group followed by whitespace (or the end of the
/// output) closes a sentence. Decimal points and common abbreviations are not
/// boundaries. A final non-empty clause without punctuation counts as one
/// sentence, while bullet or line breaks alone do not manufacture sentences.
int countSentences(String text) {
  String remaining = text.trim();
  if (remaining.isEmpty) return 0;

  remaining = remaining.replaceAllMapped(
    RegExp(r'\b(?:mr|mrs|ms|dr|prof|sr|jr|st|vs|etc)\.', caseSensitive: false),
    (Match match) => match.group(0)!.replaceAll('.', ''),
  );
  remaining = remaining.replaceAllMapped(
    RegExp(r'\b(?:e\.g|i\.e)\.', caseSensitive: false),
    (Match match) => match.group(0)!.replaceAll('.', ''),
  );
  remaining = remaining.replaceAllMapped(
    RegExp(r'\b(?:[A-Za-z]\.){2,}(?=\s+[a-z])'),
    (Match match) => match.group(0)!.replaceAll('.', ''),
  );

  final RegExp boundary = RegExp(r'''[.!?]+["'”’\)\]]*(?=\s|$)''');
  int count = 0;
  int consumedThrough = 0;
  for (final Match match in boundary.allMatches(remaining)) {
    final String before = remaining.substring(consumedThrough, match.start);
    if (before.trim().isNotEmpty) count++;
    consumedThrough = match.end;
  }

  if (remaining.substring(consumedThrough).trim().isNotEmpty) count++;
  return count;
}
