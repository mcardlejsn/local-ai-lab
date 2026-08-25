import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/recall_checklist.dart';


/// A faithful extraction of the deploy incident passage.
const String _deployCompleteOutput = '''
1. **08:30:** Deploy of build 4.2.1 started.
2. **09:15:** Error rate rose to 12% after the cache layer was restarted.
3. **09:30:** Response latency peaked at 940 ms.
4. **10:00 to 10:45:** Rollback ran and restored the previous build.
5. **12:00:** Traffic returned to baseline with 3 requests still failing.
''';

/// A faithful extraction that splits the rollback window into two entries
/// rather than writing it as a range.
const String _deploySplitWindowOutput = '''
1. **08:30**: Deploy of build 4.2.1 started
2. **09:15**: Error rate rose to 12% after the cache layer restart
3. **09:30**: Response latency peaked at 940 ms
4. **10:00**: Rollback began
5. **10:45**: Rollback completed, previous build restored
6. **12:00**: Traffic returned to baseline with 3 requests still failing
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
  final deploy = benchmarkPassage.checklist;

  group('passage identification', () {
    test('the benchmark runs the deploy incident passage', () {
      expect(defaultBenchmarkPassage, deployIncidentPassage.text);
      expect(defaultBenchmarkInstruction, deployIncidentPassage.instruction);
    });

    test('the built-in passage resolves to its checklist', () {
      expect(builtInPassageFor(benchmarkPassage.text)?.id, 'deploy_incident');
    });

    test('whitespace and casing changes still resolve', () {
      final reflowed =
          benchmarkPassage.text.replaceAll(' ', '  ').toUpperCase();
      expect(builtInPassageFor(reflowed)?.id, 'deploy_incident');
    });

    test('a session saved with another passage resolves to no checklist', () {
      final other = benchmarkPassage.text.replaceAll('940', '512');
      expect(checklistForPassage(other), isNull);
    });

    test('the passage recalls all of its own facts', () {
      expect(gradeRecall(benchmarkPassage.text, deploy).missedIds, isEmpty);
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

    test('splitting the rollback window is not counted as a drop', () {
      // "10:00 Rollback began" and "10:45 Rollback completed" keeps both times
      // faithfully; only joining them into a range should not be required.
      expect(gradeRecall(_deploySplitWindowOutput, deploy).missedIds, isEmpty);
    });

    test('a bare 12:00 is not credited as a 12% error rate', () {
      final fact = deploy.factById('error_rate_12')!;

      expect(outputContainsFact('Traffic resumed at 12:00.', fact), isFalse);
      expect(outputContainsFact('Error rate hit 12%.', fact), isTrue);
    });
  });

  group('matching rules', () {
    const latency = ExpectedFact(
      id: 'latency_940ms',
      label: 'Latency 940 ms',
      anyOf: ['940 ms', '940ms'],
    );

    test('spacing and casing inside a unit do not matter', () {
      expect(outputContainsFact('Latency hit 940 MS.', latency), isTrue);
      expect(outputContainsFact('peak: 940ms', latency), isTrue);
      expect(outputContainsFact('(940 ms)', latency), isTrue);
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
      expect(outputContainsFact('Latency hit 512 ms.', latency), isFalse);
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