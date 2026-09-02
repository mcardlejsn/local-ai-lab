import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/main.dart';
import 'package:local_ai_summarizer/models/litertlm_model_artifact.dart';
import 'package:local_ai_summarizer/screens/benchmark_screen.dart';
import 'package:local_ai_summarizer/screens/summarizer_screen.dart';
import 'package:local_ai_summarizer/services/model_manager_service.dart';

void main() {
  group('prompt-format resolution', () {
    test('Hermes takes ChatML precedence over its Llama base family', () {
      expect(
        resolvePromptFormat('Hermes-3-Llama-3.2-3B-Instruct-Q4_K_M.gguf'),
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
      expect(resolvePromptFormat('SmolLM3-Q4_K_M.gguf'), PromptFormat.smollm3);
    });

    test('recognizes Qwen3 without changing Qwen3.5 or Qwen2.5', () {
      expect(
        resolvePromptFormat('Qwen_Qwen3-1.7B-Q4_K_M.gguf'),
        PromptFormat.qwen3,
      );
      expect(
        resolvePromptFormat('Qwen_Qwen3.5-2B-Q4_K_M.gguf'),
        PromptFormat.chatml,
      );
      expect(
        resolvePromptFormat('Qwen2.5-1.5B-Instruct-Q4_K_M.gguf'),
        PromptFormat.chatml,
      );
    });

    test('recognizes the dedicated Phi-3 prompt format', () {
      expect(
        resolvePromptFormat('Phi-3.5-mini-instruct-Q4_K_M.gguf'),
        PromptFormat.phi3,
      );
    });

    test('recognizes the dedicated Phi-4 prompt format', () {
      expect(
        resolvePromptFormat('microsoft_Phi-4-mini-instruct-Q4_K_M.gguf'),
        PromptFormat.phi4,
      );
    });

    test('recognizes only the audited Falcon-H1 0.5B prompt format', () {
      expect(
        resolvePromptFormat('Falcon-H1-0.5B-Instruct-Q4_K_M.gguf'),
        PromptFormat.falconH1,
      );
      expect(
        resolvePromptFormat('Falcon-H1-1.5B-Instruct-Q4_K_M.gguf'),
        PromptFormat.plain,
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
    const String instruction = 'Summarize this:';
    const String rawText = 'A short passage.';

    test('SmolLM2 includes its official default system message', () {
      final String prompt = buildPrompt(
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
      final String prompt = buildPrompt(
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

    test('Qwen3 uses the official hard non-thinking generation prompt', () {
      final String prompt = buildPrompt(
        format: PromptFormat.qwen3,
        instruction: instruction,
        rawText: rawText,
      );

      expect(
        prompt,
        '<|im_start|>user\n'
        'Summarize this:\n\n"""\nA short passage.\n"""<|im_end|>\n'
        '<|im_start|>assistant\n'
        '<think>\n\n</think>\n\n',
      );
    });

    test('Phi-3 uses its official user-only instruction prompt', () {
      final String prompt = buildPrompt(
        format: PromptFormat.phi3,
        instruction: instruction,
        rawText: rawText,
      );

      expect(
        prompt,
        '<|user|>\n'
        'Summarize this:\n\n"""\nA short passage.\n"""<|end|>\n'
        '<|assistant|>\n',
      );
      expect(prompt, isNot(contains('<|system|>')));
    });

    test('Phi-4 uses its official user-only instruction prompt', () {
      final String prompt = buildPrompt(
        format: PromptFormat.phi4,
        instruction: instruction,
        rawText: rawText,
      );

      expect(
        prompt,
        '<|user|>\n'
        'Summarize this:\n\n"""\nA short passage.\n"""<|end|>\n'
        '<|assistant|>\n',
      );
      expect(prompt, isNot(contains('<|system|>')));
    });

    test('Falcon-H1 0.5B uses its official user-only ChatML prompt', () {
      final String prompt = buildPrompt(
        format: PromptFormat.falconH1,
        instruction: instruction,
        rawText: rawText,
      );

      expect(
        prompt,
        '<|im_start|>user\n'
        'Summarize this:\n\n"""\nA short passage.\n"""<|im_end|>\n'
        '<|im_start|>assistant\n',
      );
      expect(prompt, isNot(startsWith('<|begin_of_text|>')));
    });

    test('generic ChatML does not inherit the SmolLM2 system message', () {
      final String prompt = buildPrompt(
        format: PromptFormat.chatml,
        instruction: instruction,
        rawText: rawText,
      );

      expect(prompt, isNot(contains('named SmolLM')));
      expect(prompt, startsWith('<|im_start|>user\n'));
    });

    test('GGUF Gemma retains its resolved Gemma instruction template', () {
      final String prompt = buildInferencePrompt(
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
      final String prompt = buildInferencePrompt(
        format: PromptFormat.llama3,
        instruction: instruction,
        rawText: rawText,
      );

      expect(prompt, contains('<|start_header_id|>user<|end_header_id|>'));
      expect(prompt, contains('<|start_header_id|>assistant<|end_header_id|>'));
    });

    test('LiteRT-LM receives the unchanged plain instruction and passage', () {
      final String prompt = buildInferencePrompt(
        format: PromptFormat.plain,
        instruction: instruction,
        rawText: rawText,
      );

      expect(prompt, 'Summarize this:\n\n"""\nA short passage.\n"""');
      expect(prompt, isNot(contains('<|im_start|>')));
      expect(prompt, isNot(contains('<start_of_turn>')));
    });
  });

  group('output-token estimation', () {
    test('rounds once from the complete output', () {
      expect(estimateOutputTokens('12345'), 2);
    });

    test('does not depend on streaming chunk boundaries', () {
      const List<String> chunks = <String>['1', '2', '3', '4', '5'];
      expect(estimateOutputTokens(chunks.join()), 2);
    });
  });

  group('active model file discovery', () {
    test('accepts GGUF and every exact approved LiteRT-LM filename', () {
      expect(isActiveModelFilePath('/models/model.gguf'), isTrue);
      expect(isActiveModelFilePath('/models/MODEL.GGUF'), isTrue);
      expect(
        isActiveModelFilePath('/models/${prototypeLiteRtLmArtifact.filename}'),
        isTrue,
      );
      expect(
        isActiveModelFilePath(
          '/models/${olmo2OneBInstructLiteRtLmArtifact.filename}',
        ),
        isTrue,
      );
      expect(isActiveModelFilePath('/models/other-model.litertlm'), isFalse);
      expect(isActiveModelFilePath('/models/model.task'), isFalse);
      expect(isActiveModelFilePath('/models/model.bin'), isFalse);
    });
  });

  group('runtime sampling controls', () {
    test('disables adjustable sampling only for LiteRT-LM', () {
      expect(supportsAdjustableSamplingControls(ModelEngine.nano), isTrue);
      expect(supportsAdjustableSamplingControls(ModelEngine.gguf), isTrue);
      expect(supportsAdjustableSamplingControls(ModelEngine.litertlm), isFalse);
    });
  });

  group('benchmark model targeting', () {
    test('retains the legacy MediaPipe saved-record identity', () {
      expect(ModelEngine.values.byName('mediapipe'), ModelEngine.mediapipe);
    });

    final ModelInfo nano = ModelInfo(
      id: 'system_gemini_nano',
      name: 'Gemini Nano',
      path: 'system://aicore/nano',
      engine: ModelEngine.nano,
      sizeBytes: 0,
      promptFormat: PromptFormat.plain,
    );
    final ModelInfo candidate = ModelInfo(
      id: '/models/candidate.gguf',
      name: 'candidate.gguf',
      path: '/models/candidate.gguf',
      engine: ModelEngine.gguf,
      sizeBytes: 123,
      promptFormat: PromptFormat.chatml,
    );
    final ModelInfo qwenLiteRtLm = ModelInfo(
      id: prototypeLiteRtLmArtifact.identity,
      name: prototypeLiteRtLmArtifact.displayName,
      path: '/models/${prototypeLiteRtLmArtifact.filename}',
      engine: ModelEngine.litertlm,
      sizeBytes: prototypeLiteRtLmArtifact.sizeBytes,
      promptFormat: PromptFormat.plain,
    );
    final ModelInfo olmoLiteRtLm = ModelInfo(
      id: olmo2OneBInstructLiteRtLmArtifact.identity,
      name: olmo2OneBInstructLiteRtLmArtifact.displayName,
      path: '/models/${olmo2OneBInstructLiteRtLmArtifact.filename}',
      engine: ModelEngine.litertlm,
      sizeBytes: olmo2OneBInstructLiteRtLmArtifact.sizeBytes,
      promptFormat: PromptFormat.plain,
    );

    test('retains the platform-neutral LiteRT-LM engine identity', () {
      expect(ModelEngine.values.byName('litertlm'), ModelEngine.litertlm);
    });

    test('includes every active runtime in the benchmark model set', () {
      expect(isBenchmarkModel(nano), isTrue);
      expect(isBenchmarkModel(candidate), isTrue);
      expect(isBenchmarkModel(qwenLiteRtLm), isTrue);
      expect(isBenchmarkModel(olmoLiteRtLm), isTrue);
      expect(
        isBenchmarkModel(
          ModelInfo(
            id: 'historical-mediapipe',
            name: 'Historical MediaPipe model',
            path: '/models/historical.task',
            engine: ModelEngine.mediapipe,
            sizeBytes: 123,
            promptFormat: PromptFormat.plain,
          ),
        ),
        isFalse,
      );
    });

    test('normal suite retains multiple LiteRT-LM models', () {
      expect(
        benchmarkModelsForTarget(<ModelInfo>[
          nano,
          candidate,
          qwenLiteRtLm,
          olmoLiteRtLm,
        ]),
        <ModelInfo>[nano, candidate, qwenLiteRtLm, olmoLiteRtLm],
      );
    });

    test('normal suite retains only selected models in available order', () {
      expect(
        benchmarkModelsForTarget(
          <ModelInfo>[nano, candidate],
          selectedModelIds: <String>{candidate.id},
        ),
        <ModelInfo>[candidate],
      );
      expect(
        benchmarkModelsForTarget(
          <ModelInfo>[nano, candidate, qwenLiteRtLm, olmoLiteRtLm],
          selectedModelIds: <String>{
            olmoLiteRtLm.id,
            candidate.id,
            nano.id,
            qwenLiteRtLm.id,
          },
        ),
        <ModelInfo>[nano, candidate, qwenLiteRtLm, olmoLiteRtLm],
      );
      expect(
        benchmarkModelsForTarget(
          <ModelInfo>[nano, candidate],
          selectedModelIds: <String>{'not-installed'},
        ),
        isEmpty,
      );
    });

    test('Candidate qualification selects only the exact GGUF path', () {
      expect(
        benchmarkModelsForTarget(
          <ModelInfo>[nano, candidate],
          targetModelId: candidate.id,
          selectedModelIds: <String>{nano.id},
        ),
        <ModelInfo>[candidate],
      );
      expect(
        benchmarkModelsForTarget(
          <ModelInfo>[nano, candidate],
          targetModelId: nano.id,
        ),
        isEmpty,
      );
      expect(
        benchmarkModelsForTarget(
          <ModelInfo>[candidate, qwenLiteRtLm, olmoLiteRtLm],
          targetModelId: qwenLiteRtLm.id,
        ),
        isEmpty,
      );
      expect(
        benchmarkModelsForTarget(
          <ModelInfo>[candidate, qwenLiteRtLm, olmoLiteRtLm],
          targetModelId: olmoLiteRtLm.id,
        ),
        isEmpty,
      );
    });

    test('main suite requires two models but Candidate requires one', () {
      expect(
        canRunBenchmarkModels(
          <ModelInfo>[nano],
          isCandidateQualification: false,
        ),
        isFalse,
      );
      expect(
        canRunBenchmarkModels(
          <ModelInfo>[nano, candidate],
          isCandidateQualification: false,
        ),
        isTrue,
      );
      expect(
        canRunBenchmarkModels(
          <ModelInfo>[candidate],
          isCandidateQualification: true,
        ),
        isTrue,
      );
      expect(
        canRunBenchmarkModels(
          <ModelInfo>[],
          isCandidateQualification: true,
        ),
        isFalse,
      );
    });
  });

  testWidgets('Summarizer screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const LocalAiApp());

    expect(find.byType(SummarizerScreen), findsOneWidget);
  });
}
