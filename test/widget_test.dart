import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/main.dart';
import 'package:local_ai_summarizer/screens/summarizer_screen.dart';
import 'package:local_ai_summarizer/services/model_manager_service.dart';

void main() {
  group('inference prompt formatting', () {
    const instruction = 'Summarize this:';
    const rawText = 'A short passage.';

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
