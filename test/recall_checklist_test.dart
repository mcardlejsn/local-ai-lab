import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/recall_checklist.dart';

/// A faithful extraction of the sample deploy passage.
const String _deployCompleteOutput = '''
1. **08:30:** Deploy of build 4.2.1 started.
2. **09:15:** Error rate rose to 12% after the cache layer was restarted.
3. **09:30:** Response latency peaked at 940 ms.
4. **10:00 to 10:45:** Rollback ran and restored the previous build.
5. **12:00:** Traffic returned to baseline with 3 requests still failing.
''';

/// The same passage summarized loosely: most of the numbers dropped.
const String _deployLossyOutput = '''
- 08:30 - Deploy started.
- 09:15 - Error rate increased after a restart.
- 09:30 - Latency peaked.
- 10:00 - Rollback until 10:45.
- 12:00 - Traffic back to normal.
''';

/// Every literal the instruction asks for, with none of the events they belong
/// to. An authored checklist of timestamps scored this near-full.
const String _tokenDumpOutput =
    '08:30 09:15 09:30 10:00 10:45 12:00 4.2.1 12% 940 ms rollback 3 requests';

/// A passage the app has never seen.
const String _customPassage =
    'Patient seen at 14:20 reporting chest pain. Troponin measured 0.09 '
    'ng/mL. Discharged at 17:45 with a follow-up in 72 hours.';

void main() {
  final deploy = benchmarkPassage.profile;

  group('profiling a passage', () {
    test('the benchmark opens on the deploy sample', () {
      expect(defaultBenchmarkPassage, deployIncidentPassage.text);
      expect(defaultBenchmarkInstruction, deployIncidentPassage.instruction);
    });

    test('content words are kept and function words are not', () {
      expect(deploy.tokens, contains('rollback'));
      expect(deploy.tokens, contains('baseline'));
      expect(deploy.tokens, isNot(contains('the')));
      expect(deploy.tokens, isNot(contains('at')));
      expect(deploy.tokens, isNot(contains('and')));
    });

    test('numbers, times, metrics and versions survive whole', () {
      expect(
        deploy.tokens,
        containsAll(<String>['4.2.1', '08:30', '12%', '940', '10:45', '3']),
      );
    });

    test('a repeated word is expected once', () {
      expect(deploy.tokens.where((t) => t == 'build').length, 1);
    });

    test('an unseen passage profiles just as well', () {
      final custom = profileForPassage(_customPassage);

      expect(custom.total, greaterThan(10));
      expect(
        custom.tokens,
        containsAll(<String>['troponin', '14:20', '0.09', '72']),
      );
    });

    test('an empty passage expects nothing', () {
      final empty = profileForPassage('   ');

      expect(empty.isEmpty, isTrue);
      expect(gradeRecall('anything at all', empty).fraction, isNull);
    });
  });

  group('grading outputs', () {
    test('a passage recalls all of its own content', () {
      expect(gradeRecall(benchmarkPassage.text, deploy).missedTokens, isEmpty);
    });

    test('a faithful extraction keeps nearly everything', () {
      final result = gradeRecall(_deployCompleteOutput, deploy);

      expect(result.fraction, greaterThan(0.95));
    });

    test('a lossy summary scores well under a faithful one', () {
      final lossy = gradeRecall(_deployLossyOutput, deploy);
      final complete = gradeRecall(_deployCompleteOutput, deploy);

      expect(lossy.found, lessThan(complete.found));
      expect(
        lossy.missedTokens,
        containsAll(<String>['4.2.1', '12%', '940', 'cache']),
      );
    });

    test('a bare token dump is not credited with the content', () {
      final dump = gradeRecall(_tokenDumpOutput, deploy);

      expect(dump.fraction, lessThan(0.5));
      expect(
        dump.missedTokens,
        containsAll(<String>['deploy', 'error', 'cache', 'layer']),
      );
    });

    test('an empty output recalls nothing without erroring', () {
      final result = gradeRecall('', deploy);

      expect(result.found, 0);
      expect(result.missedTokens.length, deploy.total);
      expect(result.fraction, 0);
    });

    test('found and missed together account for the whole passage', () {
      final result = gradeRecall(_deployLossyOutput, deploy);

      expect(result.found + result.missedTokens.length, deploy.total);
      expect(result.total, deploy.total);
    });
  });

  group('matching rules', () {
    test('markdown emphasis around a timestamp does not hide it', () {
      expect(outputContainsToken('**08:30:** deploy began', '08:30'), isTrue);
    });

    test('a dropped leading zero still counts', () {
      expect(outputContainsToken('started at 8:30', '08:30'), isTrue);
    });

    test('a bare 12:00 is not credited as a 12% error rate', () {
      expect(outputContainsToken('Traffic resumed at 12:00.', '12%'), isFalse);
      expect(outputContainsToken('Error rate hit 12%.', '12%'), isTrue);
    });

    test('a number is not credited by a longer number containing it', () {
      expect(outputContainsToken('latency was 9400 ms', '940'), isFalse);
      expect(outputContainsToken('latency was 940 ms', '940'), isTrue);
    });

    test('inflected forms of a word count', () {
      expect(outputContainsToken('the cache restart finished', 'restarted'),
          isTrue);
      expect(outputContainsToken('traffic returns to normal', 'returned'),
          isTrue);
    });

    test('a stem stays specific enough not to match a different word', () {
      expect(outputContainsToken('it finished later than planned', 'latency'),
          isFalse);
    });

    test('a word inside a longer word is not credited', () {
      expect(outputContainsToken('the recache step', 'cache'), isFalse);
    });
  });
}