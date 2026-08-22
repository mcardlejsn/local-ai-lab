import 'dart:async';
import 'package:llama_flutter_android/llama_flutter_android.dart';

class LlamaGgufService {
  static LlamaController? _controller;
  static String? _loadedModelPath;

  static bool get isLoaded => _controller != null;
  static String? get loadedModelPath => _loadedModelPath;

  static Future<void> loadModel({
    required String modelPath,
    int threads = 4,
    int contextSize = 2048,
  }) async {
    if (_loadedModelPath == modelPath && _controller != null) {
      return;
    }

    await unloadModel();

    final controller = LlamaController();
    await controller.loadModel(
      modelPath: modelPath,
      threads: threads,
      contextSize: contextSize,
    );

    _controller = controller;
    _loadedModelPath = modelPath;
  }

  static Stream<String> generate({
    required String prompt,
    double temperature = 0.20,
    int topK = 40,
    int maxTokens = 256,
  }) {
    if (_controller == null) {
      throw Exception('No GGUF model loaded in memory.');
    }

    return _controller!.generate(
      prompt: prompt,
      temperature: temperature,
      topK: topK,
      maxTokens: maxTokens,
    );
  }

  static Future<void> stop() async {
    await _controller?.stop();
  }

  static Future<void> unloadModel() async {
    if (_controller != null) {
      try {
        await _controller!.stop();
        await _controller!.dispose();
      } catch (_) {}
      _controller = null;
      _loadedModelPath = null;
    }
  }
}