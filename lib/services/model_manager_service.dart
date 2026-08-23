import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'gemini_nano_service.dart';
import 'llama_gguf_service.dart';

enum ModelEngine { nano, mediapipe, gguf }

/// The instruction-tuning wrapper a model expects around a prompt. This is not
/// conversational state — it is the framing each fine-tune was trained on, and
/// sending the wrong one pushes the model off-distribution.
enum PromptFormat { plain, gemma, chatml, llama3, mistral }

extension PromptFormatLabel on PromptFormat {
  String get label {
    switch (this) {
      case PromptFormat.plain:
        return 'plain';
      case PromptFormat.gemma:
        return 'gemma';
      case PromptFormat.chatml:
        return 'chatml';
      case PromptFormat.llama3:
        return 'llama3';
      case PromptFormat.mistral:
        return 'mistral';
    }
  }
}

/// Resolves a prompt format from a model filename. Falls back to [PromptFormat.plain]
/// for anything unrecognized, since an unwrapped instruction is safer than a
/// confidently wrong wrapper.
PromptFormat resolvePromptFormat(String fileName) {
  final String name = fileName.toLowerCase();

  if (name.contains('gemma')) return PromptFormat.gemma;
  if (name.contains('llama-3') ||
      name.contains('llama3') ||
      name.contains('llama_3')) {
    return PromptFormat.llama3;
  }
  if (name.contains('mistral') || name.contains('mixtral')) {
    return PromptFormat.mistral;
  }
  if (name.contains('qwen') ||
      name.contains('chatml') ||
      name.contains('hermes')) {
    return PromptFormat.chatml;
  }

  return PromptFormat.plain;
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
    case PromptFormat.llama3:
      // BOS is emitted by the runtime, so it is deliberately omitted here to
      // avoid a duplicate begin-of-text token.
      return '<|start_header_id|>user<|end_header_id|>\n\n$body<|eot_id|>'
          '<|start_header_id|>assistant<|end_header_id|>\n\n';
    case PromptFormat.mistral:
      return '[INST] $body [/INST]';
  }
}

/// Builds the prompt delivered to an inference runtime.
///
/// The current MediaPipe path installs Gemma models from `.bin` or `.task`
/// files. MediaPipe `.bin` models require the Gemma conversation framing to be
/// supplied manually. GGUF runtimes also receive a plain string and require
/// their filename-selected instruction template to be applied here.
String buildInferencePrompt({
  required ModelEngine engine,
  required PromptFormat format,
  required String instruction,
  required String rawText,
}) {
  return buildPrompt(
    format: engine == ModelEngine.mediapipe ? PromptFormat.gemma : format,
    instruction: instruction,
    rawText: rawText,
  );
}

/// Character-based output-token proxy used consistently across runtimes.
///
/// Estimate once from the accumulated output so streaming chunk boundaries do
/// not inflate the result through repeated rounding.
int estimateOutputTokens(String output) => (output.length / 4.0).ceil();

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
  InferenceModel? _activeMediaPipeEngine;
  dynamic _activeMediaPipeSession;
  bool _isLoading = false;
  String? _statusMessage;

  List<ModelInfo> get availableModels => List.unmodifiable(_availableModels);
  ModelInfo? get activeModel => _activeModel;
  dynamic get activeMediaPipeSession => _activeMediaPipeSession;
  bool get isLoading => _isLoading;
  String? get statusMessage => _statusMessage;

  Future<List<Directory>> get _searchDirectories async {
    final List<Directory> dirs = [];
    final extDir = await getExternalStorageDirectory();
    if (extDir != null) {
      dirs.add(Directory(p.join(extDir.path, 'models')));
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
        final String? aiCoreVersion = await GeminiNanoService.getAiCoreVersion();
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

      // 2. Scan sandbox filesystem for MediaPipe (.bin, .task) and GGUF (.gguf)
      final directories = await _searchDirectories;
      for (final dir in directories) {
        if (await dir.exists()) {
          try {
            final entities = await dir.list(recursive: false).toList();
            for (final entity in entities) {
              if (entity is File) {
                final ext = p.extension(entity.path).toLowerCase();
                final fileName = p.basename(entity.path);

                if (ext == '.bin' || ext == '.task') {
                  if (!discovered.any((m) => m.path == entity.path)) {
                    final stat = await entity.stat();
                    discovered.add(
                      ModelInfo(
                        id: entity.path,
                        name: fileName,
                        path: entity.path,
                        engine: ModelEngine.mediapipe,
                        sizeBytes: stat.size,
                        // installModel pins ModelType.gemmaIt, so these are Gemma builds.
                        promptFormat: PromptFormat.gemma,
                      ),
                    );
                  }
                } else if (ext == '.gguf') {
                  if (!discovered.any((m) => m.path == entity.path)) {
                    final stat = await entity.stat();
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
          _activeModel = _availableModels.firstWhere((m) => m.id == _activeModel!.id);
          _statusMessage = _activeModel!.engine == ModelEngine.nano
              ? 'Gemini Nano Ready (AICore NPU)'
              : 'Ready: ${_activeModel!.name}';
        }
      } else {
        _activeModel = null;
        await unloadAllEngines();
        _statusMessage = 'No models found (System NPU or files/models/)';
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
      } else if (model.engine == ModelEngine.mediapipe) {
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
        ).fromFile(model.path).install();

        _activeMediaPipeEngine = await FlutterGemma.getActiveModel();
        _activeMediaPipeSession = await _activeMediaPipeEngine?.createSession();
        _activeModel = model;
        _statusMessage = 'MediaPipe Ready: ${model.name}';
      } else if (model.engine == ModelEngine.gguf) {
        await LlamaGgufService.loadModel(
          modelPath: model.path,
          threads: 4,
          contextSize: 2048,
        );
        _activeModel = model;
        _statusMessage =
            'GGUF Engine Ready: ${model.name} · ${model.promptFormat.label} prompt format';
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

  Future<void> recreateMediaPipeSession({
    required double temperature,
    required int topK,
  }) async {
    if (_activeMediaPipeEngine == null) return;
    try {
      _activeMediaPipeSession = await _activeMediaPipeEngine!.createSession(
        temperature: temperature,
        topK: topK,
      );
    } catch (e) {
      debugPrint('Error recreating MediaPipe session: $e');
    }
  }

  Future<void> unloadAllEngines() async {
    // 1. Free MediaPipe references
    _activeMediaPipeSession = null;
    _activeMediaPipeEngine = null;

    // 2. Free GGUF / llama.cpp memory
    await LlamaGgufService.unloadModel();
  }
}
