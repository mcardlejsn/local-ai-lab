import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/recall_checklist.dart';

/// Gemini Nano's output for the shift note: every expected fact present,
/// timestamps wrapped in markdown bold.
const String _nanoOutput = '''
Here are the extracted events in chronological order:

1. **08:30:** Client arrived for morning medication (Metformin 500mg, Lisinopril 10mg) with a full glass of water.
2. **09:15:** Client ate half a banana.
3. **09:30:** Blood glucose reading was 128 mg/dL.
4. **10:00 to 10:45:** Attended physical therapy session (good mobility, no complaints of pain).
5. **12:00:** Returned to the common area for lunch.
''';

/// gemma-2b's output for the same passage: both medications dropped, the
/// therapy window split across clauses, and the arrival relocated to a clinic
/// that the passage never mentions.
const String _gemmaOutput = '''
Sure, here is the chronological order of timestamps, vitals, and medication events:

- 08:30 - Client arrived at the clinic.
- 09:15 - Client ate half a banana.
- 09:30 - Blood glucose reading was 128 mg/dL.
- 10:00 - Client attended physical therapy until 10:45.
- 12:00 - Client returned for lunch.
''';

/// Llama-3.2-3B's output: same facts, different punctuation and layout.
const String _llamaOutput = '''
Here are the extracted timestamps, vitals, and medication events in chronological order:

* 08:30: Client arrived
 + Medication event: Metformin 500mg, Lisinopril 10mg
* 09:15: Ate half a banana (no vital or medication event)
* 09:30: Blood glucose reading 128mg/dL
* 10:00 - 10:45: Physical therapy session
* 12:00: Returned to common area for lunch
''';

/// A faithful extraction of the deploy incident passage.
const String _deployCompleteOutput = '''
1. **08:30:** Deploy of build 4.2.1 started.
2. **09:15:** Error rate rose to 12% after the cache layer was restarted.
3. **09:30:** Response latency peaked at 940 ms.
4. **10:00 to 10:45:** Rollback ran and restored the previous build.
5. **12:00:** Traffic returned to baseline with 3 requests still failing.
''';

/// The same passage summarized loosely: every number dropped.
const String _deployLossyOutput = '''
- 08:30 - Deploy started.
- 09:15 - Error rate increased after a restart.
- 09:30 - Latency peaked.
- 10:00 - Rollback until 10:45.
- 12:00 - Traffic back to normal.
''';

void main() {
  final shiftNote = shiftNotePassage.checklist;
  final deploy = deployIncidentPassage.checklist;

  group('passage identification', () {
    test('the app opens on the deploy incident passage', () {
      expect(defaultBenchmarkPassage, deployIncidentPassage.text);
    });

    test('each built-in passage resolves to its own checklist', () {
      expect(builtInPassageFor(deployIncidentPassage.text)?.id,
          'deploy_incident');
      expect(builtInPassageFor(shiftNotePassage.text)?.id, 'shift_note');
    });

    test('whitespace and casing changes still resolve', () {
      final reflowed = shiftNotePassage.text.replaceAll(' ', '  ').toUpperCase();
      expect(builtInPassageFor(reflowed)?.id, 'shift_note');
    });

    test('an edited passage resolves to no checklist', () {
      final edited = shiftNotePassage.text.replaceAll('128', '142');
      expect(checklistForPassage(edited), isNull);
    });

    test('every built-in passage recalls all of its own facts', () {
      for (final passage in builtInBenchmarkPassages) {
        final result = gradeRecall(passage.text, passage.checklist);
        expect(result.missedIds, isEmpty,
            reason: '${passage.id} does not contain its own expected facts');
      }
    });
  });

  group('grading real shift-note outputs', () {
    test('Nano recalls every expected fact', () {
      final result = gradeRecall(_nanoOutput, shiftNote);

      expect(result.total, shiftNote.facts.length);
      expect(result.missedIds, isEmpty);
    });

    test('gemma-2b is marked down for the dropped medications', () {
      final result = gradeRecall(_gemmaOutput, shiftNote);

      expect(
        result.missedIds,
        containsAll(<String>['med_metformin', 'med_lisinopril']),
      );
      expect(result.found, lessThan(shiftNote.facts.length));
    });

    test('the fabricated clinic does not affect recall', () {
      // Recall counts what was kept, not what was invented. This documents the
      // limit rather than asserting the fabrication is caught.
      final withoutFabrication =
          _gemmaOutput.replaceAll('arrived at the clinic', 'arrived');
      expect(
        gradeRecall(withoutFabrication, shiftNote).found,
        gradeRecall(_gemmaOutput, shiftNote).found,
      );
    });

    test('Llama recalls every expected fact despite different formatting', () {
      expect(gradeRecall(_llamaOutput, shiftNote).missedIds, isEmpty);
    });
  });

  group('grading deploy-incident outputs', () {
    test('a faithful extraction recalls every expected fact', () {
      expect(gradeRecall(_deployCompleteOutput, deploy).missedIds, isEmpty);
    });

    test('a lossy summary loses the version, rate, latency and count', () {
      final result = gradeRecall(_deployLossyOutput, deploy);

      expect(
        result.missedIds,
        containsAll(<String>[
          'build_version',
          'error_rate_12',
          'latency_940ms',
          'failing_requests_3',
        ]),
      );
    });

    test('a bare 12:00 is not credited as a 12% error rate', () {
      final fact = deploy.factById('error_rate_12')!;

      expect(outputContainsFact('Traffic resumed at 12:00.', fact), isFalse);
      expect(outputContainsFact('Error rate hit 12%.', fact), isTrue);
    });
  });

  group('matching rules', () {
    const glucose = ExpectedFact(
      id: 'vital_glucose_128',
      label: 'Blood glucose 128 mg/dL',
      anyOf: ['128 mg/dl', '128mg/dl'],
    );

    test('spacing and casing inside a unit do not matter', () {
      expect(outputContainsFact('Reading was 128 MG/dL.', glucose), isTrue);
      expect(outputContainsFact('reading: 128mg/dl', glucose), isTrue);
      expect(outputContainsFact('(128 mg / dL)', glucose), isTrue);
    });

    test('markdown emphasis around a timestamp does not hide it', () {
      const time = ExpectedFact(
        id: 'time_0830',
        label: '08:30',
        anyOf: ['08:30'],
      );

      expect(outputContainsFact('**08:30:** arrived', time), isTrue);
    });

    test('an absent fact stays absent', () {
      expect(outputContainsFact('Reading was 142 mg/dL.', glucose), isFalse);
    });
  });

  group('empty output', () {
    test('recalls nothing without erroring', () {
      final result = gradeRecall('', deploy);

      expect(result.found, 0);
      expect(result.missedIds.length, deploy.facts.length);
      expect(result.fraction, 0);
    });
  });
}