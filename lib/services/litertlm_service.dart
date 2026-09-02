import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:path/path.dart' as p;

import '../models/litertlm_model_artifact.dart';

/// Platform-neutral accelerator identity used by the application layer.
///
/// The LiteRT-LM package maps [gpu] to OpenCL on Android and Metal on iOS.
enum InferenceBackend { cpu, gpu, npu, unknown }

abstract interface class LiteRtLmRuntime {
  Future<void> initialize();

  Future<LiteRtLmModelHandle> loadModel({
    required String modelPath,
    required int contextTokens,
    required InferenceBackend preferredBackend,
    required LiteRtLmRuntimeProfile runtimeProfile,
    required bool isThinking,
  });
}

abstract interface class LiteRtLmModelHandle {
  InferenceBackend get activeBackend;

  Future<Stream<String>> generate({
    required String prompt,
    required double temperature,
    required int topK,
    required int maxOutputTokens,
  });

  Future<void> stop();
  Future<void> close();
}

/// Maps the app-level artifact profile to flutter_gemma's runtime model type.
ModelType liteRtLmFlutterModelType(LiteRtLmRuntimeProfile profile) {
  return switch (profile) {
    LiteRtLmRuntimeProfile.general => ModelType.general,
    LiteRtLmRuntimeProfile.qwen3 => ModelType.qwen3,
  };
}

class LiteRtLmService {
  LiteRtLmService({LiteRtLmRuntime? runtime})
    : _runtime = runtime ?? FlutterGemmaLiteRtLmRuntime();

  static final LiteRtLmService instance = LiteRtLmService();

  /// LiteRT-LM 0.16 GPU executors ignore session-level sampler settings and
  /// currently construct the sampler with these native defaults. Keep the
  /// application fixed to the same values until the upstream runtime honors
  /// adjustable sampling and Local AI Lab deliberately restores the controls.
  static const double fixedGpuTemperature = 1.0;
  static const int fixedGpuTopK = 1;
  static const int fixedGpuSeed = 0;

  final LiteRtLmRuntime _runtime;
  LiteRtLmModelHandle? _handle;
  String? _loadedModelPath;
  LiteRtLmModelArtifact? _loadedArtifact;

  bool get isLoaded => _handle != null;
  String? get loadedModelPath => _loadedModelPath;
  LiteRtLmModelArtifact? get loadedArtifact => _loadedArtifact;

  Future<void> loadModel(String modelPath) async {
    final LiteRtLmModelArtifact? artifact = liteRtLmArtifactForFilename(
      p.basename(modelPath),
    );
    if (artifact == null) {
      throw ArgumentError.value(
        modelPath,
        'modelPath',
        'Unknown or unapproved LiteRT-LM artifact',
      );
    }

    if (_loadedModelPath == modelPath && _handle != null) return;

    await unloadModel();
    await _runtime.initialize();

    final LiteRtLmModelHandle handle = await _runtime.loadModel(
      modelPath: modelPath,
      contextTokens: artifact.contextTokens,
      preferredBackend: InferenceBackend.gpu,
      runtimeProfile: artifact.runtimeProfile,
      isThinking: artifact.isThinking,
    );

    if (handle.activeBackend != InferenceBackend.gpu) {
      try {
        await handle.close();
      } catch (_) {}
      throw StateError(
        'LiteRT-LM GPU initialization failed. '
        'CPU fallback was refused for this model.',
      );
    }

    _handle = handle;
    _loadedModelPath = modelPath;
    _loadedArtifact = artifact;
  }

  /// Starts a fresh isolated chat and streams one generation.
  ///
  /// Sampling remains fixed to the LiteRT-LM GPU executor's effective native
  /// values. Run and Compare deliberately share this same contract.
  Future<Stream<String>> generate({
    required String prompt,
    int maxOutputTokens = 256,
  }) {
    final LiteRtLmModelHandle? handle = _handle;
    if (handle == null) {
      throw StateError('No LiteRT-LM model loaded in memory.');
    }
    return handle.generate(
      prompt: prompt,
      temperature: fixedGpuTemperature,
      topK: fixedGpuTopK,
      maxOutputTokens: maxOutputTokens,
    );
  }

  Future<void> stop() async {
    await _handle?.stop();
  }

  Future<void> unloadModel() async {
    final LiteRtLmModelHandle? handle = _handle;
    _handle = null;
    _loadedModelPath = null;
    _loadedArtifact = null;
    if (handle != null) await handle.close();
  }
}

class FlutterGemmaLiteRtLmRuntime implements LiteRtLmRuntime {
  Future<void>? _initialization;

  @override
  Future<void> initialize() async {
    final Future<void>? current = _initialization;
    if (current != null) return current;

    final initialization = FlutterGemma.initialize(
      inferenceEngines: const [LiteRtLmEngine()],
    );
    _initialization = initialization;
    try {
      await initialization;
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  @override
  Future<LiteRtLmModelHandle> loadModel({
    required String modelPath,
    required int contextTokens,
    required InferenceBackend preferredBackend,
    required LiteRtLmRuntimeProfile runtimeProfile,
    required bool isThinking,
  }) async {
    final ModelType modelType = liteRtLmFlutterModelType(runtimeProfile);
    await FlutterGemma.installModel(
      modelType: modelType,
      fileType: ModelFileType.litertlm,
    ).fromFile(modelPath).install();

    final InferenceModel model = await FlutterGemma.getActiveModel(
      maxTokens: contextTokens,
      preferredBackend: _preferredBackend(preferredBackend),
    );
    return FlutterGemmaLiteRtLmModelHandle(
      model,
      modelType: modelType,
      isThinking: isThinking,
    );
  }

  PreferredBackend _preferredBackend(InferenceBackend backend) {
    return switch (backend) {
      InferenceBackend.cpu => PreferredBackend.cpu,
      InferenceBackend.gpu => PreferredBackend.gpu,
      InferenceBackend.npu => PreferredBackend.npu,
      InferenceBackend.unknown => PreferredBackend.gpu,
    };
  }
}

class FlutterGemmaLiteRtLmModelHandle implements LiteRtLmModelHandle {
  FlutterGemmaLiteRtLmModelHandle(
    this._model, {
    required this._modelType,
    required this._isThinking,
  });

  final InferenceModel _model;
  final ModelType _modelType;
  final bool _isThinking;
  InferenceChat? _chat;

  @override
  InferenceBackend get activeBackend => switch (_model.activeBackend) {
    PreferredBackend.cpu => InferenceBackend.cpu,
    PreferredBackend.gpu => InferenceBackend.gpu,
    PreferredBackend.npu => InferenceBackend.npu,
    null => InferenceBackend.unknown,
  };

  @override
  Future<Stream<String>> generate({
    required String prompt,
    required double temperature,
    required int topK,
    required int maxOutputTokens,
  }) async {
    final InferenceChat? previous = _chat;
    _chat = null;
    if (previous != null) await previous.close();

    final InferenceChat chat = await _model.createChat(
      temperature: temperature,
      randomSeed: LiteRtLmService.fixedGpuSeed,
      topK: topK,
      isThinking: _isThinking,
      modelType: _modelType,
      maxOutputTokens: maxOutputTokens,
    );
    _chat = chat;
    await chat.addQueryChunk(Message(text: prompt, isUser: true));
    return chat
        .generateChatResponseAsync()
        .where((response) => response is TextResponse)
        .map((response) => (response as TextResponse).token);
  }

  @override
  Future<void> stop() async {
    await _chat?.stopGeneration();
  }

  @override
  Future<void> close() async {
    final InferenceChat? chat = _chat;
    _chat = null;
    if (chat != null) {
      try {
        await chat.stopGeneration();
      } catch (_) {}
      try {
        await chat.close();
      } catch (_) {}
    }
    await _model.close();
  }
}
