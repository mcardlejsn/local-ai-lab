import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/main.dart';
import 'package:local_ai_summarizer/screens/summarizer_screen.dart';
import 'package:local_ai_summarizer/services/model_manager_service.dart';

void main() {
  group('prompt-format resolution', () {
    test('Hermes takes ChatML precedence over its Llama base family', () {
      expect(
        resolvePromptFormat(
          'Hermes-3-Llama-3.2-3B-Instruct-Q4_K_M.gguf',
        ),
        PromptFormat.chatml,
      );
    });

    test('explicit ChatML takes precedence over a Llama family name', () {
      expect(
        resolvePromptFormat('Llama-3.2-1B-Instruct-ChatML-Q4_K_M.gguf'),
        PromptFormat.chatml,
      );
    });

    test('recognizes the dedicated SmolLM2 prompt format', () {
      expect(
        resolvePromptFormat('smollm2-1.7b-instruct-q4_k_m.gguf'),
        PromptFormat.smollm2,
      );
    });

    test('recognizes the dedicated SmolLM3 prompt format', () {
      expect(
        resolvePromptFormat('SmolLM3-Q4_K_M.gguf'),
        PromptFormat.smollm3,
      );
    });

    test('recognizes existing supported filename families', () {
      expect(
        resolvePromptFormat('Llama-3.2-1B-Instruct-Q4_K_M.gguf'),
        PromptFormat.llama3,
      );
      expect(
        resolvePromptFormat('Qwen2.5-1.5B-Instruct-Q4_K_M.gguf'),
        PromptFormat.chatml,
      );
      expect(
        resolvePromptFormat('gemma-3-1b-it-Q4_K_M.gguf'),
        PromptFormat.gemma,
      );
      expect(
        resolvePromptFormat('Mistral-7B-Instruct-Q4_K_M.gguf'),
        PromptFormat.mistral,
      );
      expect(
        resolvePromptFormat('Mixtral-8x7B-Instruct-Q4_K_M.gguf'),
        PromptFormat.mistral,
      );
    });

    test('falls back to plain for an unknown filename family', () {
      expect(
        resolvePromptFormat('unknown-model-Q4_K_M.gguf'),
        PromptFormat.plain,
      );
    });
  });

  group('inference prompt formatting', () {
    const instruction = 'Summarize this:';
    const rawText = 'A short passage.';

    test('SmolLM2 includes its official default system message', () {
      final prompt = buildPrompt(
        format: PromptFormat.smollm2,
        instruction: instruction,
        rawText: rawText,
      );

      expect(
        prompt,
        '<|im_start|>system\n'
        'You are a helpful AI assistant named SmolLM, trained by Hugging Face<|im_end|>\n'
        '<|im_start|>user\n'
        'Summarize this:\n\n"""\nA short passage.\n"""<|im_end|>\n'
        '<|im_start|>assistant\n',
      );
    });

    test('SmolLM3 uses a stable non-thinking prompt', () {
      final prompt = buildPrompt(
        format: PromptFormat.smollm3,
        instruction: instruction,
        rawText: rawText,
      );

      expect(
        prompt,
        '<|im_start|>system\n'
        'You are a helpful AI assistant named SmolLM, trained by Hugging Face.<|im_end|>\n'
        '<|im_start|>user\n'
        'Summarize this:\n\n"""\nA short passage.\n"""<|im_end|>\n'
        '<|im_start|>assistant\n'
        '<think>\n\n</think>\n',
      );
      expect(prompt, isNot(contains('Today Date:')));
    });

    test('generic ChatML does not inherit the SmolLM2 system message', () {
      final prompt = buildPrompt(
        format: PromptFormat.chatml,
        instruction: instruction,
        rawText: rawText,
      );

      expect(prompt, isNot(contains('named SmolLM')));
      expect(prompt, startsWith('<|im_start|>user\n'));
    });

    test('MediaPipe retains the manual Gemma template required by .bin', () {
      final prompt = buildInferencePrompt(
        engine: ModelEngine.mediapipe,
        format: PromptFormat.gemma,
        instruction: instruction,
        rawText: rawText,
      );

      expect(prompt, contains(instruction));
      expect(prompt, contains(rawText));
      expect(prompt, contains('<start_of_turn>user'));
      expect(prompt, contains('<start_of_turn>model'));
    });

    test('GGUF retains its resolved instruction template', () {
      final prompt = buildInferencePrompt(
        engine: ModelEngine.gguf,
        format: PromptFormat.llama3,
        instruction: instruction,
        rawText: rawText,
      );

      expect(prompt, contains('<|start_header_id|>user<|end_header_id|>'));
      expect(prompt, contains('<|start_header_id|>assistant<|end_header_id|>'));
    });
  });

  group('output-token estimation', () {
    test('rounds once from the complete output', () {
      expect(estimateOutputTokens('12345'), 2);
    });

    test('does not depend on streaming chunk boundaries', () {
      const chunks = ['1', '2', '3', '4', '5'];
      expect(estimateOutputTokens(chunks.join()), 2);
    });
  });

  testWidgets('Summarizer screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const LocalAiApp());

    expect(find.byType(SummarizerScreen), findsOneWidget);
  });
}
