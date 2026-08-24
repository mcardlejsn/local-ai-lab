/// Deterministic recall grading: how many of a passage's expected facts appear
/// in a model's output. No model is involved in grading — a fact is either
/// found by string match or it is not.
///
/// Recall is not accuracy. It counts what the output kept, and says nothing
/// about what it invented; a run can score full recall and still fabricate.
/// Faithfulness stays a manual judgement.
library;

/// One fact a faithful output is expected to carry.
class ExpectedFact {
  const ExpectedFact({
    required this.id,
    required this.label,
    required this.anyOf,
    this.normalizedOnly = false,
  });

  /// Stable identifier, stored with results so a saved run can name what it
  /// missed without re-running the matcher.
  final String id;

  /// Human-readable description, shown in the output modal.
  final String label;

  /// Accepted surface forms. The fact counts as found if any one of them
  /// appears in the output.
  final List<String> anyOf;

  /// Skips the punctuation-insensitive pass for facts whose meaning lives in
  /// their punctuation. `12%` would otherwise match the `12` inside `12:00`.
  final bool normalizedOnly;
}

/// The set of facts expected for one passage, bound to that passage by
/// fingerprint so an edited passage can't be graded against a stale list.
class RecallChecklist {
  const RecallChecklist({
    required this.passageFingerprint,
    required this.facts,
  });

  final String passageFingerprint;
  final List<ExpectedFact> facts;

  int get total => facts.length;

  ExpectedFact? factById(String id) {
    for (final fact in facts) {
      if (fact.id == id) return fact;
    }
    return null;
  }
}

/// A built-in passage and the facts it expects. The passage text is the control
/// variable for a benchmark run, so these are fixed rather than generated.
class BenchmarkPassage {
  const BenchmarkPassage({
    required this.id,
    required this.name,
    required this.text,
    required this.instruction,
    required this.facts,
  });

  final String id;

  /// Short label for the picker.
  final String name;

  final String text;

  /// The instruction this passage is meant to be run with. Travels with the
  /// passage so the task always describes what the text actually contains.
  final String instruction;

  final List<ExpectedFact> facts;

  RecallChecklist get checklist => RecallChecklist(
        passageFingerprint: fingerprintPassage(text),
        facts: facts,
      );
}

/// Outcome of grading one output against a checklist.
class RecallResult {
  const RecallResult({
    required this.foundIds,
    required this.missedIds,
    required this.total,
  });

  final List<String> foundIds;
  final List<String> missedIds;
  final int total;

  int get found => foundIds.length;

  /// Recall as a fraction of expected facts, or null for an empty checklist.
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

/// Reduces text to letters and digits only, so `940 ms`, `940ms` and
/// `(940 ms)` all compare equal.
String compactForRecall(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// Fingerprint of a passage's content. FNV-1a, 32-bit, computed over the
/// normalized text so whitespace and casing edits don't invalidate a checklist
/// but wording changes do.
String fingerprintPassage(String passage) {
  const int offsetBasis = 0x811c9dc5;
  const int prime = 0x01000193;

  int hash = offsetBasis;
  for (final unit in normalizeForRecall(passage).codeUnits) {
    hash = (hash ^ unit) & 0xFFFFFFFF;
    hash = (hash * prime) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// True when [output] carries [fact] in any of its accepted forms.
bool outputContainsFact(String output, ExpectedFact fact) {
  final normalized = normalizeForRecall(output);
  final compact = compactForRecall(output);

  for (final form in fact.anyOf) {
    if (normalized.contains(normalizeForRecall(form))) return true;
    if (!fact.normalizedOnly && compact.contains(compactForRecall(form))) {
      return true;
    }
  }
  return false;
}

/// Grades one output against [checklist].
RecallResult gradeRecall(String output, RecallChecklist checklist) {
  final found = <String>[];
  final missed = <String>[];

  for (final fact in checklist.facts) {
    if (outputContainsFact(output, fact)) {
      found.add(fact.id);
    } else {
      missed.add(fact.id);
    }
  }

  return RecallResult(
    foundIds: found,
    missedIds: missed,
    total: checklist.facts.length,
  );
}

/// Default passage: a deployment timeline. Dense with timestamps, units, a
/// version string and a duration window, which is the shape that small models
/// drop facts from, without reading as anyone's personal record.
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
  facts: [
    ExpectedFact(
      id: 'time_0830',
      label: '08:30 — deploy started',
      anyOf: ['08:30', '8:30'],
    ),
    ExpectedFact(
      id: 'build_version',
      label: 'Build 4.2.1',
      anyOf: ['4.2.1'],
    ),
    ExpectedFact(
      id: 'error_rate_12',
      label: 'Error rate 12%',
      anyOf: ['12%', '12 %'],
      normalizedOnly: true,
    ),
    ExpectedFact(
      id: 'time_0915',
      label: '09:15 — error rate rose',
      anyOf: ['09:15', '9:15'],
    ),
    ExpectedFact(
      id: 'cache_restart',
      label: 'Cache layer restarted',
      anyOf: ['cache layer', 'cache'],
    ),
    ExpectedFact(
      id: 'time_0930',
      label: '09:30 — latency peaked',
      anyOf: ['09:30', '9:30'],
    ),
    ExpectedFact(
      id: 'latency_940ms',
      label: 'Latency 940 ms',
      anyOf: ['940 ms', '940ms'],
    ),
    ExpectedFact(
      id: 'event_rollback',
      label: 'Rollback to previous build',
      anyOf: ['rollback', 'rolled back'],
    ),
    ExpectedFact(
      id: 'time_1000_1045',
      label: '10:00 to 10:45 — rollback window',
      anyOf: ['10:00 to 10:45', '10:00-10:45', '10:00 - 10:45'],
    ),
    ExpectedFact(
      id: 'time_1200',
      label: '12:00 — traffic back to baseline',
      anyOf: ['12:00'],
    ),
    ExpectedFact(
      id: 'failing_requests_3',
      label: '3 requests still failing',
      anyOf: ['3 requests'],
    ),
  ],
);

/// The passage every benchmark runs. Fixed on purpose: it is the control
/// variable, so results stay comparable across sessions and devices.
const BenchmarkPassage benchmarkPassage = deployIncidentPassage;

/// Text the benchmark screen runs.
String get defaultBenchmarkPassage => benchmarkPassage.text;

/// Instruction the benchmark screen runs it with.
String get defaultBenchmarkInstruction => benchmarkPassage.instruction;

/// The built-in passage matching [passage], or null for anything else —
/// including sessions saved before the passage was fixed.
BenchmarkPassage? builtInPassageFor(String passage) {
  return fingerprintPassage(passage) ==
          fingerprintPassage(benchmarkPassage.text)
      ? benchmarkPassage
      : null;
}

/// The checklist for [passage], or null when the passage isn't the built-in
/// one. A null result means recall grading is unavailable, not that the output
/// scored zero.
RecallChecklist? checklistForPassage(String passage) {
  return builtInPassageFor(passage)?.checklist;
}