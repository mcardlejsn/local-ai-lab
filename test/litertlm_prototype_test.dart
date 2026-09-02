import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/litertlm_model_artifact.dart';
import 'package:local_ai_summarizer/services/litertlm_service.dart';

void main() {
  group('exact LiteRT-LM artifact catalog', () {
    test('retains the audited Qwen repository and artifact identity', () {
      expect(
        prototypeLiteRtLmArtifact.repository,
        'litert-community/Qwen3-0.6B',
      );
      expect(
        prototypeLiteRtLmArtifact.revision,
        '8414150f2e9dcc82449bcc9c5abc404b399a4d06',
      );
      expect(
        prototypeLiteRtLmArtifact.filename,
        'qwen3_0_6b_mixed_int4.litertlm',
      );
      expect(prototypeLiteRtLmArtifact.sizeBytes, 497664000);
      expect(
        prototypeLiteRtLmArtifact.sha256,
        'b1baab462f6be49d70eada79d715c2c52cd9ece0cad00bddf6a2c097d23498e9',
      );
      expect(prototypeLiteRtLmArtifact.license, 'Apache-2.0');
      expect(prototypeLiteRtLmArtifact.contextTokens, 2048);
      expect(
        prototypeLiteRtLmArtifact.runtimeProfile,
        LiteRtLmRuntimeProfile.qwen3,
      );
      expect(prototypeLiteRtLmArtifact.isThinking, isFalse);
      expect(
        prototypeLiteRtLmArtifact.downloadUrl,
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/'
        '8414150f2e9dcc82449bcc9c5abc404b399a4d06/'
        'qwen3_0_6b_mixed_int4.litertlm',
      );
    });

    test('pins the corrected OLMo artifact and general runtime profile', () {
      expect(
        olmo2OneBInstructLiteRtLmArtifact.repository,
        'litert-community/OLMo-2-1B-Instruct',
      );
      expect(
        olmo2OneBInstructLiteRtLmArtifact.revision,
        'f94e362b82804bab977df6da9a63352598ca45cb',
      );
      expect(
        olmo2OneBInstructLiteRtLmArtifact.filename,
        'OLMo-2-1B-Instruct_q4_block32_ekv4096.litertlm',
      );
      expect(olmo2OneBInstructLiteRtLmArtifact.sizeBytes, 931241056);
      expect(
        olmo2OneBInstructLiteRtLmArtifact.sha256,
        '8d2457b54397731c5f451babb6bebfb9877545b4b070ac76914aab348fd954b0',
      );
      expect(olmo2OneBInstructLiteRtLmArtifact.license, 'Apache-2.0');
      expect(olmo2OneBInstructLiteRtLmArtifact.contextTokens, 4096);
      expect(
        olmo2OneBInstructLiteRtLmArtifact.runtimeProfile,
        LiteRtLmRuntimeProfile.general,
      );
      expect(olmo2OneBInstructLiteRtLmArtifact.isThinking, isFalse);
    });

    test('resolves only approved exact filenames', () {
      expect(
        liteRtLmArtifactForFilename(prototypeLiteRtLmArtifact.filename),
        same(prototypeLiteRtLmArtifact),
      );
      expect(
        liteRtLmArtifactForFilename(olmo2OneBInstructLiteRtLmArtifact.filename),
        same(olmo2OneBInstructLiteRtLmArtifact),
      );
      expect(liteRtLmArtifactForFilename('renamed.litertlm'), isNull);
      expect(
        liteRtLmArtifactForFilename(
          olmo2OneBInstructLiteRtLmArtifact.filename.toLowerCase(),
        ),
        isNull,
      );
    });

    test('requires exact filename, byte size, and SHA-256', () {
      const LiteRtLmModelArtifact artifact = olmo2OneBInstructLiteRtLmArtifact;
      expect(
        artifact.matchesVerifiedIdentity(
          candidateFilename: artifact.filename,
          candidateSizeBytes: artifact.sizeBytes,
          candidateSha256: artifact.sha256.toUpperCase(),
        ),
        isTrue,
      );
      expect(
        artifact.matchesVerifiedIdentity(
          candidateFilename: 'renamed.litertlm',
          candidateSizeBytes: artifact.sizeBytes,
          candidateSha256: artifact.sha256,
        ),
        isFalse,
      );
      expect(
        artifact.matchesVerifiedIdentity(
          candidateFilename: artifact.filename,
          candidateSizeBytes: artifact.sizeBytes - 1,
          candidateSha256: artifact.sha256,
        ),
        isFalse,
      );
      expect(
        artifact.matchesVerifiedIdentity(
          candidateFilename: artifact.filename,
          candidateSizeBytes: artifact.sizeBytes,
          candidateSha256: List<String>.filled(64, '0').join(),
        ),
        isFalse,
      );
    });

    test('maps app profiles to the installed flutter_gemma model types', () {
      expect(
        liteRtLmFlutterModelType(LiteRtLmRuntimeProfile.qwen3),
        ModelType.qwen3,
      );
      expect(
        liteRtLmFlutterModelType(LiteRtLmRuntimeProfile.general),
        ModelType.general,
      );
    });
  });

  group('LiteRT-LM runtime guard and lifecycle', () {
    test('uses Qwen profile with fixed GPU sampling', () async {
      final _FakeModelHandle handle = _FakeModelHandle(
        activeBackend: InferenceBackend.gpu,
        responses: const <List<String>>[
          <String>['First ', 'response.'],
          <String>['Second response.'],
        ],
      );
      final _FakeRuntime runtime = _FakeRuntime(handle);
      final LiteRtLmService service = LiteRtLmService(runtime: runtime);
      final String modelPath = '/models/${prototypeLiteRtLmArtifact.filename}';

      await service.loadModel(modelPath);
      final Stream<String> first = await service.generate(
        prompt: 'Prompt one',
        maxOutputTokens: 42,
      );
      final Stream<String> second = await service.generate(
        prompt: 'Prompt two',
        maxOutputTokens: 12,
      );

      expect(await first.join(), 'First response.');
      expect(await second.join(), 'Second response.');
      expect(runtime.initializeCalls, 1);
      expect(runtime.requestedModelPath, modelPath);
      expect(runtime.requestedBackend, InferenceBackend.gpu);
      expect(runtime.requestedContextTokens, 2048);
      expect(runtime.requestedRuntimeProfile, LiteRtLmRuntimeProfile.qwen3);
      expect(runtime.requestedIsThinking, isFalse);
      expect(service.loadedArtifact, same(prototypeLiteRtLmArtifact));
      expect(handle.requests, hasLength(2));
      expect(handle.requests[0].prompt, 'Prompt one');
      expect(
        handle.requests[0].temperature,
        LiteRtLmService.fixedGpuTemperature,
      );
      expect(handle.requests[0].topK, LiteRtLmService.fixedGpuTopK);
      expect(handle.requests[0].maxOutputTokens, 42);
      expect(
        handle.requests[1].temperature,
        LiteRtLmService.fixedGpuTemperature,
      );
      expect(handle.requests[1].topK, LiteRtLmService.fixedGpuTopK);
      expect(handle.requests[1].maxOutputTokens, 12);
      expect(LiteRtLmService.fixedGpuSeed, 0);
    });

    test('loads OLMo with its general non-thinking profile', () async {
      final _FakeModelHandle handle = _FakeModelHandle(
        activeBackend: InferenceBackend.gpu,
        responses: const <List<String>>[],
      );
      final _FakeRuntime runtime = _FakeRuntime(handle);
      final LiteRtLmService service = LiteRtLmService(runtime: runtime);
      final String modelPath =
          '/models/${olmo2OneBInstructLiteRtLmArtifact.filename}';

      await service.loadModel(modelPath);

      expect(runtime.requestedModelPath, modelPath);
      expect(runtime.requestedContextTokens, 4096);
      expect(runtime.requestedRuntimeProfile, LiteRtLmRuntimeProfile.general);
      expect(runtime.requestedIsThinking, isFalse);
      expect(service.loadedArtifact, same(olmo2OneBInstructLiteRtLmArtifact));
    });

    test(
      'rejects an unknown LiteRT-LM artifact before initialization',
      () async {
        final _FakeRuntime runtime = _FakeRuntime(
          _FakeModelHandle(
            activeBackend: InferenceBackend.gpu,
            responses: const <List<String>>[],
          ),
        );
        final LiteRtLmService service = LiteRtLmService(runtime: runtime);

        await expectLater(
          service.loadModel('/models/unknown.litertlm'),
          throwsA(isA<ArgumentError>()),
        );
        expect(runtime.initializeCalls, 0);
        expect(service.isLoaded, isFalse);
      },
    );

    test('supports stop and unload', () async {
      final _FakeModelHandle handle = _FakeModelHandle(
        activeBackend: InferenceBackend.gpu,
        responses: const <List<String>>[],
      );
      final LiteRtLmService service = LiteRtLmService(
        runtime: _FakeRuntime(handle),
      );

      await service.loadModel('/models/${prototypeLiteRtLmArtifact.filename}');
      await service.stop();
      await service.unloadModel();

      expect(handle.stopCalls, 1);
      expect(handle.closeCalls, 1);
      expect(service.isLoaded, isFalse);
      expect(service.loadedModelPath, isNull);
      expect(service.loadedArtifact, isNull);
    });

    test('refuses a silent CPU fallback before generation', () async {
      final _FakeModelHandle handle = _FakeModelHandle(
        activeBackend: InferenceBackend.cpu,
        responses: const <List<String>>[],
      );
      final LiteRtLmService service = LiteRtLmService(
        runtime: _FakeRuntime(handle),
      );

      await expectLater(
        service.loadModel('/models/${prototypeLiteRtLmArtifact.filename}'),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            contains('CPU fallback was refused'),
          ),
        ),
      );
      expect(handle.closeCalls, 1);
      expect(service.isLoaded, isFalse);
      expect(service.loadedArtifact, isNull);
    });
  });
}

class _GenerationRequest {
  const _GenerationRequest({
    required this.prompt,
    required this.temperature,
    required this.topK,
    required this.maxOutputTokens,
  });

  final String prompt;
  final double temperature;
  final int topK;
  final int maxOutputTokens;
}

class _FakeRuntime implements LiteRtLmRuntime {
  _FakeRuntime(this.handle);

  final _FakeModelHandle handle;
  int initializeCalls = 0;
  String? requestedModelPath;
  int? requestedContextTokens;
  InferenceBackend? requestedBackend;
  LiteRtLmRuntimeProfile? requestedRuntimeProfile;
  bool? requestedIsThinking;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<LiteRtLmModelHandle> loadModel({
    required String modelPath,
    required int contextTokens,
    required InferenceBackend preferredBackend,
    required LiteRtLmRuntimeProfile runtimeProfile,
    required bool isThinking,
  }) async {
    requestedModelPath = modelPath;
    requestedContextTokens = contextTokens;
    requestedBackend = preferredBackend;
    requestedRuntimeProfile = runtimeProfile;
    requestedIsThinking = isThinking;
    return handle;
  }
}

class _FakeModelHandle implements LiteRtLmModelHandle {
  _FakeModelHandle({required this.activeBackend, required this.responses});

  @override
  final InferenceBackend activeBackend;
  final List<List<String>> responses;
  final List<_GenerationRequest> requests = <_GenerationRequest>[];
  int stopCalls = 0;
  int closeCalls = 0;

  @override
  Future<Stream<String>> generate({
    required String prompt,
    required double temperature,
    required int topK,
    required int maxOutputTokens,
  }) async {
    requests.add(
      _GenerationRequest(
        prompt: prompt,
        temperature: temperature,
        topK: topK,
        maxOutputTokens: maxOutputTokens,
      ),
    );
    return Stream<String>.fromIterable(responses[requests.length - 1]);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }
}
