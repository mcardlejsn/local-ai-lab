import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ModelInfo {
  final String name;
  final String path;
  final int sizeBytes;

  ModelInfo({
    required this.name,
    required this.path,
    required this.sizeBytes,
  });

  String get formattedSize {
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
  InferenceModel? _activeEngine;
  dynamic _activeSession;
  bool _isLoading = false;
  String? _statusMessage;

  List<ModelInfo> get availableModels => List.unmodifiable(_availableModels);
  ModelInfo? get activeModel => _activeModel;
  dynamic get activeSession => _activeSession;
  bool get isLoading => _isLoading;
  String? get statusMessage => _statusMessage;

  Future<Directory> get _modelsDirectory async {
    final extDir = await getExternalStorageDirectory();
    final modelsPath = p.join(extDir!.path, 'models');
    final dir = Directory(modelsPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> scanModels() async {
    _isLoading = true;
    _statusMessage = 'Scanning models directory...';
    notifyListeners();

    try {
      final dir = await _modelsDirectory;
      final entities = dir.listSync();
      final List<ModelInfo> discovered = [];

      for (final entity in entities) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (ext == '.bin' || ext == '.task') {
            final stat = await entity.stat();
            discovered.add(
              ModelInfo(
                name: p.basename(entity.path),
                path: entity.path,
                sizeBytes: stat.size,
              ),
            );
          }
        }
      }

      _availableModels = discovered;

      if (_availableModels.isNotEmpty) {
        if (_activeModel == null ||
            !_availableModels.any((m) => m.path == _activeModel!.path)) {
          await loadModel(_availableModels.first);
          return;
        }
      } else {
        _activeModel = null;
        await _disposeCurrentEngine();
        _statusMessage = 'No .bin or .task files found in files/models/';
      }
    } catch (e) {
      _statusMessage = 'Error scanning models: $e';
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
      await _disposeCurrentEngine();

      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromFile(model.path)
          .install();

      _activeEngine = await FlutterGemma.getActiveModel();
      _activeSession = await _activeEngine?.createSession();
      _activeModel = model;
      _statusMessage = 'Ready: ${model.name}';
    } catch (e) {
      _statusMessage = 'Failed loading ${model.name}: $e';
      _activeModel = null;
      await _disposeCurrentEngine();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> recreateSession({
    required double temperature,
    required int topK,
  }) async {
    if (_activeEngine == null) return;
    try {
      if (_activeSession != null) {
        try {
          await _activeSession.dispose();
        } catch (_) {}
      }
      _activeSession = await _activeEngine!.createSession(
        temperature: temperature,
        topK: topK,
      );
    } catch (e) {
      debugPrint('Error recreating session: $e');
    }
  }

  Future<void> _disposeCurrentEngine() async {
    if (_activeSession != null) {
      try {
        await _activeSession.dispose();
      } catch (_) {}
      _activeSession = null;
    }
    _activeEngine = null;
  }
}