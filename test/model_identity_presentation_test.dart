import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/presentation/model_identity_presentation.dart';
import 'package:local_ai_summarizer/services/model_manager_service.dart';

void main() {
  group('concise model names', () {
    test('normalizes the approved active model identities', () {
      expect(
        conciseModelName(
          'Gemini Nano (base model: nano-v4; '
          'AICore service: 0.release.prod_aicore_20260723)',
          ModelEngine.nano,
        ),
        'Gemini Nano',
      );
      expect(
        conciseModelName('Qwen3 0.6B (LiteRT-LM)', ModelEngine.litertlm),
        'Qwen3 0.6B',
      );
      expect(
        conciseModelName(
          'OLMo 2 1B Instruct (LiteRT-LM)',
          ModelEngine.litertlm,
        ),
        'OLMo 2 1B Instruct',
      );
      expect(
        conciseModelName(
          'Falcon-H1-0.5B-Instruct-Q4_K_M.gguf',
          ModelEngine.gguf,
        ),
        'Falcon-H1 0.5B Instruct',
      );
      expect(
        conciseModelName('qwen2.5-0.5b-instruct-q4_k_m.gguf', ModelEngine.gguf),
        'Qwen2.5 0.5B Instruct',
      );
      expect(
        conciseModelName('Llama-3.2-3B-Instruct.Q4_K_M.gguf', ModelEngine.gguf),
        'Llama 3.2 3B Instruct',
      );
      expect(
        conciseModelName('Llama-3.2-1B-Instruct-Q4_K_M.gguf', ModelEngine.gguf),
        'Llama 3.2 1B Instruct',
      );
    });

    test('keeps historical Nano identities readable', () {
      expect(
        conciseModelName(
          'Gemini Nano (AICore 0.release.prod_aicore_20260723)',
          ModelEngine.nano,
        ),
        'Gemini Nano',
      );
    });

    test('keeps unfamiliar identity text instead of guessing a family', () {
      expect(
        conciseModelName(
          'unknown-model-1B-instruct-Q4_K_M.gguf',
          ModelEngine.gguf,
        ),
        'unknown model 1B Instruct',
      );
    });
  });

  group('Nano technical identity', () {
    test('labels the base model separately from the AICore service', () {
      expect(
        nanoTechnicalModelName(
          baseModelName: 'nano-v4',
          aiCoreVersion: '0.release.prod_aicore_20260723',
        ),
        'Gemini Nano (base model: nano-v4; '
        'AICore service: 0.release.prod_aicore_20260723)',
      );
    });

    test('does not infer missing attribution values', () {
      expect(
        nanoTechnicalModelName(),
        'Gemini Nano (base model: unavailable; '
        'AICore service: unavailable)',
      );
    });
  });

  test(
    'runtime labels cover active runtimes without calling MediaPipe legacy',
    () {
      expect(modelRuntimeLabel(ModelEngine.nano), 'AICore');
      expect(modelRuntimeLabel(ModelEngine.gguf), 'GGUF');
      expect(modelRuntimeLabel(ModelEngine.litertlm), 'LiteRT-LM');
      expect(modelRuntimeLabel(ModelEngine.mediapipe), 'MediaPipe');
    },
  );

  test('collisions gain a source suffix only where needed', () {
    final Map<String, String> names =
        resolveConciseModelNames(const <ModelDisplayIdentity>[
          ModelDisplayIdentity(
            key: 'a',
            technicalName: 'bartowski_Qwen2.5-0.5B-Instruct-Q4_K_M.gguf',
            engine: ModelEngine.gguf,
            publisherHint: 'bartowski',
          ),
          ModelDisplayIdentity(
            key: 'b',
            technicalName: 'unsloth_Qwen2.5-0.5B-Instruct-Q4_K_M.gguf',
            engine: ModelEngine.gguf,
            publisherHint: 'unsloth',
          ),
          ModelDisplayIdentity(
            key: 'c',
            technicalName: 'Falcon-H1-0.5B-Instruct-Q4_K_M.gguf',
            engine: ModelEngine.gguf,
          ),
        ]);

    expect(names['a'], 'Qwen2.5 0.5B Instruct — Bartowski');
    expect(names['b'], 'Qwen2.5 0.5B Instruct — Unsloth');
    expect(names['c'], 'Falcon-H1 0.5B Instruct');
  });

  test(
    'Nano collisions use base-model attribution instead of service builds',
    () {
      final Map<String, String> names =
          resolveConciseModelNames(const <ModelDisplayIdentity>[
            ModelDisplayIdentity(
              key: 'current',
              technicalName:
                  'Gemini Nano (base model: nano-v4-full; '
                  'AICore service: 0.release.prod_aicore_20260723)',
              engine: ModelEngine.nano,
            ),
            ModelDisplayIdentity(
              key: 'unavailable',
              technicalName:
                  'Gemini Nano (base model: unavailable; '
                  'AICore service: 0.release.prod_aicore_20260723)',
              engine: ModelEngine.nano,
            ),
            ModelDisplayIdentity(
              key: 'historical',
              technicalName:
                  'Gemini Nano '
                  '(AICore 0.release.prod_aicore_20260723)',
              engine: ModelEngine.nano,
            ),
          ]);

      expect(names['current'], 'Gemini Nano — nano-v4-full');
      expect(names['unavailable'], 'Gemini Nano — base model unavailable');
      expect(names['historical'], 'Gemini Nano — base model unreported');
    },
  );

  test('loading status uses the pending model concise name', () {
    final String status = conciseModelStatus(
      'Initializing qwen2.5-0.5b-instruct-q4_k_m.gguf...',
      const <ModelDisplayIdentity>[
        ModelDisplayIdentity(
          key: 'falcon',
          technicalName: 'Falcon-H1-0.5B-Instruct-Q4_K_M.gguf',
          engine: ModelEngine.gguf,
        ),
        ModelDisplayIdentity(
          key: 'qwen',
          technicalName: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
          engine: ModelEngine.gguf,
        ),
      ],
    );

    expect(status, 'Initializing Qwen2.5 0.5B Instruct...');
  });
}
