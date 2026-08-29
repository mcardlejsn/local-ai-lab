import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/litertlm_model_artifact.dart';
import 'package:local_ai_summarizer/services/litertlm_service.dart';

void main() {
  group('exact LiteRT-LM prototype artifact', () {
    test('pins the audited repository revision and artifact identity', () {
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
        prototypeLiteRtLmArtifact.downloadUrl,
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/'
        '8414150f2e9dcc82449bcc9c5abc404b399a4d06/'
        'qwen3_0_6b_mixed_int4.litertlm',
      );
    });

    test('requires exact filename, byte size, and SHA-256', () {
      expect(
        prototypeLiteRtLmArtifact.matchesVerifiedIdentity(
          candidateFilename: prototypeLiteRtLmArtifact.filename,
          candidateSizeBytes: prototypeLiteRtLmArtifact.sizeBytes,
          candidateSha256: prototypeLiteRtLmArtifact.sha256.toUpperCase(),
        ),
        isTrue,
      );
      expect(
        prototypeLiteRtLmArtifact.matchesVerifiedIdentity(
          candidateFilename: 'renamed.litertlm',
          candidateSizeBytes: prototypeLiteRtLmArtifact.sizeBytes,
          candidateSha256: prototypeLiteRtLmArtifact.sha256,
        ),
        isFalse,
      );
      expect(
        prototypeLiteRtLmArtifact.matchesVerifiedIdentity(
          candidateFilename: prototypeLiteRtLmArtifact.filename,
          candidateSizeBytes: prototypeLiteRtLmArtifact.sizeBytes - 1,
          candidateSha256: prototypeLiteRtLmArtifact.sha256,
        ),
        isFalse,
      );
    });
  });

  group('LiteRT-LM runtime guard and lifecycle', () {
    test('uses fixed GPU sampling and forwards max output tokens', () async {
      final handle = _FakeModelHandle(
        activeBackend: InferenceBackend.gpu,
        responses: const [
          ['First ', 'response.'],
          ['Second response.'],
        ],
      );
      final runtime = _FakeRuntime(handle);
      final service = LiteRtLmService(runtime: runtime);

      await service.loadModel('/models/model.litertlm');
      final first = await service.generate(
        prompt: 'Prompt one',
        maxOutputTokens: 42,
      );
      final second = await service.generate(
        prompt: 'Prompt two',
        maxOutputTokens: 12,
      );

      expect(await first.join(), 'First response.');
      expect(await second.join(), 'Second response.');
      expect(runtime.initializeCalls, 1);
      expect(runtime.requestedBackend, InferenceBackend.gpu);
      expect(runtime.requestedContextTokens, 2048);
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

    test('supports stop and unload', () async {
      final handle = _FakeModelHandle(
        activeBackend: InferenceBackend.gpu,
        responses: const [],
      );
      final service = LiteRtLmService(runtime: _FakeRuntime(handle));

      await service.loadModel('/models/model.litertlm');
      await service.stop();
      await service.unloadModel();

      expect(handle.stopCalls, 1);
      expect(handle.closeCalls, 1);
      expect(service.isLoaded, isFalse);
      expect(service.loadedModelPath, isNull);
    });

    test('refuses a silent CPU fallback before generation', () async {
      final handle = _FakeModelHandle(
        activeBackend: InferenceBackend.cpu,
        responses: const [],
      );
      final service = LiteRtLmService(runtime: _FakeRuntime(handle));

      await expectLater(
        service.loadModel('/models/model.litertlm'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('CPU fallback was refused'),
          ),
        ),
      );
      expect(handle.closeCalls, 1);
      expect(service.isLoaded, isFalse);
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
  int? requestedContextTokens;
  InferenceBackend? requestedBackend;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<LiteRtLmModelHandle> loadModel({
    required String modelPath,
    required int contextTokens,
    required InferenceBackend preferredBackend,
  }) async {
    requestedContextTokens = contextTokens;
    requestedBackend = preferredBackend;
    return handle;
  }
}

class _FakeModelHandle implements LiteRtLmModelHandle {
  _FakeModelHandle({required this.activeBackend, required this.responses});

  @override
  final InferenceBackend activeBackend;
  final List<List<String>> responses;
  final List<_GenerationRequest> requests = [];
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
