/// Deterministic recall grading: how much of the passage's content survives
/// into a model's output. No model is involved in grading — a content word is
/// either present or it is not.
///
/// The expected content is derived from whatever passage is being run, so a
/// custom passage grades exactly like the built-in one. Nothing is authored
/// per passage and nothing has to match a known text.
///
/// Recall is not accuracy. It counts what the output kept, and says nothing
/// about what it invented; a run can score full recall and still fabricate.
/// Faithfulness stays a manual judgement.
library;

/// A passage and the instruction it is meant to be run with.
class BenchmarkPassage {
  const BenchmarkPassage({
    required this.id,
    required this.name,
    required this.text,
    required this.instruction,
  });

  final String id;

  /// Short label.
  final String name;

  final String text;

  /// The instruction this passage is meant to be run with. Travels with the
  /// passage so the task always describes what the text actually contains.
  final String instruction;

  PassageProfile get profile => profileForPassage(text);
}

/// The content words a passage expects an output to carry, in the order they
/// first appear. Derived, never authored.
class PassageProfile {
  const PassageProfile(this.tokens);

  /// Unique content tokens: everything left after stripping function words.
  /// Numbers, times, percentages and version strings survive whole.
  final List<String> tokens;

  int get total => tokens.length;

  bool get isEmpty => tokens.isEmpty;
}

/// Outcome of grading one output against a profile.
class RecallResult {
  const RecallResult({
    required this.foundTokens,
    required this.missedTokens,
    required this.total,
  });

  final List<String> foundTokens;
  final List<String> missedTokens;
  final int total;

  int get found => foundTokens.length;

  /// Recall as a fraction of expected content, or null for an empty passage.
  double? get fraction => total == 0 ? null : found / total;
}

/// Lowercases, strips the markdown models wrap around timestamps, and collapses
/// whitespace, so `**08:30:**` and `08:30` compare equal.
String normalizeForRecall(String value) {
  final withoutMarkdown = value.replaceAll(RegExp(r'[*_`#>]'), ' ');
  return withoutMarkdown
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Function words carry no content, so an output isn't credited or penalised
/// for them. Deliberately conservative: anything not listed here counts.
const Set<String> recallStopWords = <String>{
  'a', 'about', 'after', 'again', 'all', 'also', 'an', 'and', 'any', 'are',
  'as', 'at', 'be', 'because', 'been', 'before', 'being', 'both', 'but', 'by',
  'can', 'could', 'did', 'do', 'does', 'during', 'each', 'either', 'for',
  'from', 'further', 'had', 'has', 'have', 'having', 'here', 'how', 'however',
  'if', 'in', 'into', 'is', 'it', 'its', 'just', 'may', 'might', 'more',
  'most', 'must', 'no', 'nor', 'not', 'now', 'of', 'off', 'on', 'once',
  'only', 'or', 'other', 'our', 'out', 'over', 'own', 'said', 'same', 'shall',
  'should', 'since', 'so', 'some', 'still', 'such', 'than', 'that', 'the',
  'their', 'them', 'then', 'there', 'these', 'they', 'this', 'those',
  'through', 'thus', 'to', 'too', 'under', 'until', 'up', 'upon', 'very',
  'was', 'we', 'were', 'what', 'when', 'where', 'which', 'while', 'who',
  'whom', 'why', 'will', 'with', 'within', 'without', 'would', 'you', 'your',
};

/// Anything that isn't part of a word, a number, or a compound like `08:30`,
/// `4.2.1`, `12%` or `re-run`.
final RegExp _tokenSeparator = RegExp("[^a-z0-9:%.'\\-/]+");

/// Punctuation that can sit on either end of a token without belonging to it —
/// a trailing sentence period, a stray hyphen from a bullet list.
final RegExp _tokenEdges = RegExp("^[.:'\\-/]+|[.:'\\-/]+\$");

final RegExp _hasDigit = RegExp(r'[0-9]');

/// `08:30` and `8:30` are the same timestamp; models drop the leading zero.
final RegExp _paddedTime = RegExp(r'^0(\d:\d{2})$');

/// The content tokens of [passage], deduplicated, in order of first
/// appearance. A token is kept when it carries a digit — timestamps, metrics,
/// counts, version strings — or when it is a word of three or more letters
/// that isn't a function word.
List<String> passageContentTokens(String passage) {
  final seen = <String>{};
  final tokens = <String>[];

  for (final raw in normalizeForRecall(passage).split(_tokenSeparator)) {
    final token = raw.replaceAll(_tokenEdges, '');
    if (token.isEmpty) continue;

    final keep = _hasDigit.hasMatch(token)
        ? true
        : token.length >= 3 && !recallStopWords.contains(token);
    if (!keep) continue;

    if (seen.add(token)) tokens.add(token);
  }

  return tokens;
}

/// The content [PassageProfile] of [passage]. Works on any text — there is no
/// built-in list to match against.
PassageProfile profileForPassage(String passage) {
  return PassageProfile(passageContentTokens(passage));
}

String _escapeForRegExp(String value) {
  return value.replaceAllMapped(
    RegExp(r'[.*+?^${}()|[\]\\/%-]'),
    (match) => '\\${match[0]}',
  );
}

/// Matcher for one content token. Words are matched from their stem, so
/// `restarted` is credited by `restart` or `restarts`; anything carrying a
/// digit is matched exactly, so `12%` is never credited by the `12` inside
/// `12:00`.
RegExp tokenPattern(String token) {
  if (_hasDigit.hasMatch(token)) {
    final forms = <String>[token];
    final padded = _paddedTime.firstMatch(token);
    if (padded != null) forms.add(padded.group(1)!);

    final body = forms.map(_escapeForRegExp).join('|');
    return RegExp('(?<![a-z0-9])(?:$body)(?![a-z0-9])');
  }

  // Trim up to three characters of inflection, never below five, so `latency`
  // stays specific enough not to be credited by `later`.
  final int stemLength = token.length <= 5
      ? token.length
      : (token.length - 3 < 5 ? 5 : token.length - 3);
  final stem = _escapeForRegExp(token.substring(0, stemLength));
  return RegExp('(?<![a-z])$stem[a-z]*');
}

/// True when [normalizedOutput] carries [token]. Expects output that has
/// already been through [normalizeForRecall].
bool normalizedOutputContainsToken(String normalizedOutput, String token) {
  return tokenPattern(token).hasMatch(normalizedOutput);
}

/// True when [output] carries [token].
bool outputContainsToken(String output, String token) {
  return normalizedOutputContainsToken(normalizeForRecall(output), token);
}

/// Grades one output against [profile].
RecallResult gradeRecall(String output, PassageProfile profile) {
  final normalized = normalizeForRecall(output);
  final found = <String>[];
  final missed = <String>[];

  for (final token in profile.tokens) {
    if (normalizedOutputContainsToken(normalized, token)) {
      found.add(token);
    } else {
      missed.add(token);
    }
  }

  return RecallResult(
    foundTokens: found,
    missedTokens: missed,
    total: profile.tokens.length,
  );
}

/// Sample passage: a deployment timeline. Dense with timestamps, units, a
/// version string and a duration window, which is the shape small models drop
/// content from, without reading as anyone's personal record. It is only a
/// starting text — the passage field is editable and recall follows whatever
/// is in it.
const BenchmarkPassage deployIncidentPassage = BenchmarkPassage(
  id: 'deploy_incident',
  name: 'Deploy incident',
  instruction:
      'Extract all timestamps, metrics, and deployment events chronologically:',
  text: 'Deploy of build 4.2.1 started at 08:30. Error rate rose to 12% at '
      '09:15 after the cache layer was restarted. Response latency peaked at '
      '940 ms at 09:30. Rollback ran from 10:00 to 10:45 and restored the '
      'previous build. Traffic returned to baseline at 12:00 with 3 requests '
      'still failing.',
);

/// The passage the benchmark screen opens on.
const BenchmarkPassage benchmarkPassage = deployIncidentPassage;

/// Text the benchmark screen starts with.
String get defaultBenchmarkPassage => benchmarkPassage.text;

/// Instruction the benchmark screen starts with.
String get defaultBenchmarkInstruction => benchmarkPassage.instruction;