import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'gemini_nano_service.dart';
import 'llama_gguf_service.dart';

enum ModelEngine { nano, mediapipe, gguf }

class ModelInfo {
  final String id;
  final String name;
  final String path;
  final ModelEngine engine;
  final int sizeBytes;

  ModelInfo({
    required this.id,
    required this.name,
    required this.path,
    required this.engine,
    required this.sizeBytes,
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
        discovered.add(
          ModelInfo(
            id: 'system_gemini_nano',
            name: 'Gemini Nano (AICore NPU)',
            path: 'system://aicore/nano',
            engine: ModelEngine.nano,
            sizeBytes: 0,
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
        _statusMessage = 'GGUF Engine Ready: ${model.name}';
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