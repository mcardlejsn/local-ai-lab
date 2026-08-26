import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/gguf_compatibility_policy.dart';

void main() {
  group('GGUF compatibility policy', () {
    test('marks an audited family as discovery eligible', () {
      final assessment = assessGgufCompatibility(
        'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
      );

      expect(assessment.family, 'Qwen/ChatML');
      expect(assessment.promptFormat, PromptFormat.chatml);
      expect(assessment.isRecognized, isTrue);
      expect(assessment.isSupported, isTrue);
      expect(assessment.discoveryEligible, isTrue);
    });

    test('keeps Falcon-H1 support limited to the audited 0.5B variant', () {
      final supported = assessGgufCompatibility(
        'Falcon-H1-0.5B-Instruct-Q4_K_M.gguf',
      );
      final unaudited = assessGgufCompatibility(
        'Falcon-H1-1.5B-Instruct-Q4_K_M.gguf',
      );

      expect(supported.promptFormat, PromptFormat.falconH1);
      expect(supported.discoveryEligible, isTrue);
      expect(unaudited.promptFormat, PromptFormat.plain);
      expect(unaudited.isRecognized, isTrue);
      expect(unaudited.isSupported, isFalse);
      expect(unaudited.discoveryEligible, isFalse);
    });

    test('records the audited Qwen3.5 2B incompatibility exactly', () {
      final assessment = assessGgufCompatibility(
        'Qwen_Qwen3.5-2B-Q4_K_M.gguf',
      );

      // Preserve the previous prompt-resolution result for sideloaded files.
      expect(assessment.promptFormat, PromptFormat.chatml);
      expect(
        resolvePromptFormat('Qwen_Qwen3.5-2B-Q4_K_M.gguf'),
        PromptFormat.chatml,
      );
      expect(assessment.isRecognized, isTrue);
      expect(assessment.isSupported, isFalse);
      expect(assessment.discoveryEligible, isFalse);
      expect(assessment.family, 'Qwen3.5 2B');
      expect(assessment.explanation, contains('incompatible'));
    });

    test('does not generalize the Qwen3.5 2B result to other variants', () {
      final assessment = assessGgufCompatibility(
        'Qwen3.5-4B-Instruct-Q4_K_M.gguf',
      );

      expect(assessment.promptFormat, PromptFormat.chatml);
      expect(assessment.isRecognized, isTrue);
      expect(assessment.isSupported, isFalse);
      expect(assessment.discoveryEligible, isFalse);
      expect(assessment.family, 'Qwen3.5');
      expect(
        assessment.explanation,
        contains('not been independently audited'),
      );
    });

    test('keeps unknown sideloaded files on the plain prompt fallback', () {
      final assessment = assessGgufCompatibility(
        'unknown-model-Q4_K_M.gguf',
      );

      expect(assessment.promptFormat, PromptFormat.plain);
      expect(assessment.isRecognized, isFalse);
      expect(assessment.isSupported, isFalse);
      expect(assessment.discoveryEligible, isFalse);
      expect(
        resolvePromptFormat('unknown-model-Q4_K_M.gguf'),
        PromptFormat.plain,
      );
    });

    test('retains ChatML precedence over a Llama base-family name', () {
      final assessment = assessGgufCompatibility(
        'Hermes-3-Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      );

      expect(assessment.family, 'ChatML/Hermes');
      expect(assessment.promptFormat, PromptFormat.chatml);
      expect(assessment.discoveryEligible, isTrue);
    });
  });
}
