import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/gguf_compatibility_policy.dart';
import '../models/litertlm_model_artifact.dart';
import 'gemini_nano_service.dart';
import 'litertlm_service.dart';
import 'llama_gguf_service.dart';

export '../models/gguf_compatibility_policy.dart';

enum ModelEngine {
  nano,

  /// Retained only so previously saved benchmark rows remain readable.
  /// Active discovery and inference no longer create MediaPipe models.
  mediapipe,

  gguf,

  /// LiteRT-LM identity remains platform-neutral; the prototype runtime
  /// currently supplies its GPU implementation on Android.
  litertlm,
}

/// Wraps [instruction] and [rawText] in the framing [format] expects.
String buildPrompt({
  required PromptFormat format,
  required String instruction,
  required String rawText,
}) {
  final String body = '$instruction\n\n"""\n$rawText\n"""';

  switch (format) {
    case PromptFormat.plain:
      return body;
    case PromptFormat.gemma:
      return '<start_of_turn>user\n$body<end_of_turn>\n<start_of_turn>model\n';
    case PromptFormat.chatml:
      return '<|im_start|>user\n$body<|im_end|>\n<|im_start|>assistant\n';
    case PromptFormat.falconH1:
      // Falcon-H1's official template begins with BOS. The runtime emits BOS,
      // so it is deliberately omitted here to avoid a duplicate token.
      return '<|im_start|>user\n$body<|im_end|>\n<|im_start|>assistant\n';
    case PromptFormat.qwen3:
      // The raw llama.cpp path cannot pass enable_thinking=false to Qwen3's
      // tokenizer template. Reproduce the official hard non-thinking
      // generation prompt by prefilling an empty thinking block.
      return '<|im_start|>user\n$body<|im_end|>\n'
          '<|im_start|>assistant\n'
          '<think>\n\n</think>\n\n';
    case PromptFormat.phi3:
      return '<|user|>\n$body<|end|>\n<|assistant|>\n';
    case PromptFormat.phi4:
      return '<|user|>\n$body<|end|>\n<|assistant|>\n';
    case PromptFormat.smollm2:
      return '<|im_start|>system\n'
          'You are a helpful AI assistant named SmolLM, trained by Hugging Face<|im_end|>\n'
          '<|im_start|>user\n$body<|im_end|>\n'
          '<|im_start|>assistant\n';
    case PromptFormat.smollm3:
      // SmolLM3 normally injects the current date into its system metadata.
      // Use its supported system-override path so repeated benchmarks keep a
      // stable prompt, and prefill the empty think block required by the
      // official non-thinking template.
      return '<|im_start|>system\n'
          'You are a helpful AI assistant named SmolLM, trained by Hugging Face.<|im_end|>\n'
          '<|im_start|>user\n$body<|im_end|>\n'
          '<|im_start|>assistant\n'
          '<think>\n\n</think>\n';
    case PromptFormat.llama3:
      // BOS is emitted by the runtime, so it is deliberately omitted here to
      // avoid a duplicate begin-of-text token.
      return '<|start_header_id|>user<|end_header_id|>\n\n$body<|eot_id|>'
          '<|start_header_id|>assistant<|end_header_id|>\n\n';
    case PromptFormat.mistral:
      return '[INST] $body [/INST]';
  }
}

/// Builds the prompt delivered to an inference runtime. GGUF models receive a
/// plain string and require their filename-selected instruction template to be
/// applied here. Gemini Nano uses [PromptFormat.plain].
String buildInferencePrompt({
  required PromptFormat format,
  required String instruction,
  required String rawText,
}) {
  return buildPrompt(
    format: format,
    instruction: instruction,
    rawText: rawText,
  );
}

/// Character-based output-token proxy used consistently across runtimes.
///
/// Estimate once from the accumulated output so streaming chunk boundaries do
/// not inflate the result through repeated rounding.
int estimateOutputTokens(String output) => (output.length / 4.0).ceil();

/// Whether [filePath] can be discovered by the active file-model runtime.
bool isActiveModelFilePath(String filePath) {
  return p.extension(filePath).toLowerCase() == '.gguf' ||
      prototypeLiteRtLmArtifact.hasExpectedFilename(p.basename(filePath));
}

/// Keeps the LiteRT-LM prototype out of Benchmark Suite without coupling the
/// benchmark screen to a new engine it does not yet support.
bool isBenchmarkModel(ModelInfo model) => model.engine != ModelEngine.litertlm;

Future<String> _calculateSha256(String filePath) {
  return Isolate.run(() async {
    final digest = await sha256.bind(File(filePath).openRead()).first;
    return digest.toString();
  });
}

class ModelInfo {
  final String id;
  final String name;
  final String path;
  final ModelEngine engine;
  final int sizeBytes;
  final PromptFormat promptFormat;

  ModelInfo({
    required this.id,
    required this.name,
    required this.path,
    required this.engine,
    required this.sizeBytes,
    required this.promptFormat,
  });

  String get formattedSize {
    if (sizeBytes == 0) return 'System NPU';
    final double sizeMb = sizeBytes / (1024 * 1024);
    if (sizeMb >= 1024) {
      return '${(sizeMb / 1024).toStringAsFixed(2)} GB';
    }
    return '${sizeMb.toStringAsFixed(0)} MB';
  }
}

class ModelManagerService extends ChangeNotifier {
  static final ModelManagerService _instance = ModelManagerService._internal();
  factory ModelManagerService() => _instance;
  ModelManagerService._internal();

  List<ModelInfo> _availableModels = [];
  ModelInfo? _activeModel;
  bool _isLoading = false;
  String? _statusMessage;

  /// Models available to screens that predate the LiteRT-LM prototype.
  /// Benchmark Suite and download presentation therefore remain unchanged.
  List<ModelInfo> get availableModels =>
      List.unmodifiable(_availableModels.where(isBenchmarkModel));

  /// Every active inference model exposed by the main Summarizer.
  List<ModelInfo> get summarizerModels => List.unmodifiable(_availableModels);
  ModelInfo? get activeModel => _activeModel;
  bool get isLoading => _isLoading;
  String? get statusMessage => _statusMessage;

  Future<List<Directory>> get _searchDirectories async {
    final List<Directory> dirs = [];
    final extDir = await getExternalStorageDirectory();
    if (extDir != null) {
      dirs.add(extDir);
    }
    return dirs;
  }

  Future<void> scanModels() async {
    _isLoading = true;
    _statusMessage = 'Scanning for models...';
    notifyListeners();

    try {
      final List<ModelInfo> discovered = [];

      // 1. Check Gemini Nano (AICore NPU)
      final bool isNanoReady = await GeminiNanoService.isAvailable();
      if (isNanoReady) {
        // Capture which AICore build is serving Nano, so results recorded on
        // different devices or dates can be attributed to a specific version.
        final String? aiCoreVersion =
            await GeminiNanoService.getAiCoreVersion();
        discovered.add(
          ModelInfo(
            id: 'system_gemini_nano',
            name: aiCoreVersion == null
                ? 'Gemini Nano (AICore NPU)'
                : 'Gemini Nano (AICore $aiCoreVersion)',
            path: 'system://aicore/nano',
            engine: ModelEngine.nano,
            sizeBytes: 0,
            promptFormat: PromptFormat.plain,
          ),
        );
      }

      // 2. Scan sandbox filesystem for GGUF models and the one exact,
      // manually sideloaded LiteRT-LM prototype artifact.
      final directories = await _searchDirectories;
      for (final dir in directories) {
        if (await dir.exists()) {
          try {
            final entities = await dir.list(recursive: false).toList();
            for (final entity in entities) {
              if (entity is File) {
                final fileName = p.basename(entity.path);

                if (!isActiveModelFilePath(entity.path) ||
                    discovered.any((m) => m.path == entity.path)) {
                  continue;
                }

                final stat = await entity.stat();
                if (prototypeLiteRtLmArtifact.hasExpectedFilename(fileName)) {
                  if (stat.size != prototypeLiteRtLmArtifact.sizeBytes) {
                    debugPrint(
                      'Ignoring LiteRT-LM artifact with unexpected size: '
                      '${entity.path}',
                    );
                    continue;
                  }

                  final digest = await _calculateSha256(entity.path);
                  if (!prototypeLiteRtLmArtifact.matchesVerifiedIdentity(
                    candidateFilename: fileName,
                    candidateSizeBytes: stat.size,
                    candidateSha256: digest,
                  )) {
                    debugPrint(
                      'Ignoring LiteRT-LM artifact with unexpected SHA-256: '
                      '${entity.path}',
                    );
                    continue;
                  }

                  discovered.add(
                    ModelInfo(
                      id: prototypeLiteRtLmArtifact.identity,
                      name: prototypeLiteRtLmArtifact.displayName,
                      path: entity.path,
                      engine: ModelEngine.litertlm,
                      sizeBytes: stat.size,
                      // LiteRT-LM owns the Qwen conversation template. The
                      // app supplies only the unchanged instruction/body.
                      promptFormat: PromptFormat.plain,
                    ),
                  );
                } else {
                  discovered.add(
                    ModelInfo(
                      id: entity.path,
                      name: fileName,
                      path: entity.path,
                      engine: ModelEngine.gguf,
                      sizeBytes: stat.size,
                      promptFormat: resolvePromptFormat(fileName),
                    ),
                  );
                }
              }
            }
          } catch (e) {
            debugPrint('Error scanning ${dir.path}: $e');
          }
        }
      }

      _availableModels = discovered;

      if (_availableModels.isNotEmpty) {
        if (_activeModel == null ||
            !_availableModels.any((m) => m.id == _activeModel!.id)) {
          await loadModel(_availableModels.first);
          return;
        } else {
          // Sync existing model reference and clear loading status message
          _activeModel = _availableModels.firstWhere(
            (m) => m.id == _activeModel!.id,
          );
          _statusMessage = switch (_activeModel!.engine) {
            ModelEngine.nano => 'Gemini Nano Ready (AICore NPU)',
            ModelEngine.litertlm =>
              'LiteRT-LM Engine Ready: ${_activeModel!.name} · GPU backend',
            _ => 'Ready: ${_activeModel!.name}',
          };
        }
      } else {
        _activeModel = null;
        await unloadAllEngines();
        _statusMessage = 'No models found (System NPU or files/)';
      }
    } catch (e) {
      _statusMessage = 'Scan error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadModel(ModelInfo model) async {
    _isLoading = true;
    _statusMessage = 'Initializing ${model.name}...';
    notifyListeners();

    try {
      // Release any previously loaded runtime to prevent dual-model OOM crashes
      await unloadAllEngines();

      if (model.engine == ModelEngine.nano) {
        _activeModel = model;
        _statusMessage = 'Gemini Nano Ready (AICore NPU)';
      } else if (model.engine == ModelEngine.gguf) {
        await LlamaGgufService.loadModel(
          modelPath: model.path,
          threads: 4,
          contextSize: 2048,
        );
        _activeModel = model;
        _statusMessage =
            'GGUF Engine Ready: ${model.name} · '
            '${model.promptFormat.label} prompt format';
      } else if (model.engine == ModelEngine.litertlm) {
        await LiteRtLmService.instance.loadModel(model.path);
        _activeModel = model;
        _statusMessage = 'LiteRT-LM Engine Ready: ${model.name} · GPU backend';
      } else {
        throw UnsupportedError('This saved engine is no longer active.');
      }
    } catch (e) {
      _statusMessage = 'Failed loading ${model.name}: $e';
      _activeModel = null;
      await unloadAllEngines();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> unloadAllEngines() async {
    // Free file-backed runtimes. Gemini Nano is managed by AICore.
    await Future.wait([
      LiteRtLmService.instance.unloadModel(),
      LlamaGgufService.unloadModel(),
    ]);
  }

  /// Removes a model file from disk and rescans.
  ///
  /// Returns true if the file was deleted. Gemini Nano is served by AICore and
  /// has no file here, so it is refused rather than silently ignored.
  Future<bool> deleteModel(ModelInfo model) async {
    if (model.engine == ModelEngine.nano) {
      _statusMessage =
          'Gemini Nano is managed by Android and cannot be removed';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _statusMessage = 'Removing ${model.name}...';
    notifyListeners();

    try {
      // The runtime holds an open handle to this path. Unlinking underneath a
      // loaded engine leaves it reading a file that no longer has a name, so
      // the engine is released first.
      if (_activeModel?.id == model.id) {
        await unloadAllEngines();
        _activeModel = null;
      }

      final File file = File(model.path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      _statusMessage = 'Could not remove ${model.name}: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }

    // scanModels rebuilds the list and loads whatever remains.
    _isLoading = false;
    await scanModels();
    return true;
  }
}
