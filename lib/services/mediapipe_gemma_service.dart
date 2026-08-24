import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

/// Owns the MediaPipe (Gemma `.bin` / `.task`) engine lifecycle: installing a
/// model from file, creating and recreating its session, streaming inference,
/// and releasing references.
///
/// Model discovery and active-engine selection stay in `ModelManagerService`;
/// this service only handles the MediaPipe runtime once a model has been
/// chosen. Timing and telemetry stay with the callers, which measure
/// differently — the summarizer updates rates per chunk against a live
/// subscription, the benchmark awaits completion against a stopwatch.
class MediaPipeGemmaService {
  MediaPipeGemmaService._();

  static InferenceModel? _engine;
  static dynamic _session;

  static dynamic get session => _session;
  static bool get hasSession => _session != null;

  /// Installs [modelPath] as the active MediaPipe model and captures the
  /// resulting engine. Any prior session reference is dropped, since it belongs
  /// to the model being replaced.
  static Future<void> install(String modelPath) async {
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
    ).fromFile(modelPath).install();

    _engine = await FlutterGemma.getActiveModel();
    _session = null;
  }

  /// Creates a session on the installed engine. Omitted parameters are not
  /// forwarded, so the plugin applies its own defaults exactly as it did when
  /// each call site constructed its session directly.
  ///
  /// Throws whatever the plugin throws; callers that treat a session failure as
  /// a load or run error rely on that.
  static Future<void> createSession({
    double? temperature,
    int? topK,
    int? randomSeed,
  }) async {
    final engine = _engine;
    if (engine == null) {
      _session = null;
      return;
    }

    if (temperature == null && topK == null && randomSeed == null) {
      _session = await engine.createSession();
    } else if (randomSeed == null) {
      _session = await engine.createSession(
        temperature: temperature!,
        topK: topK!,
      );
    } else {
      _session = await engine.createSession(
        temperature: temperature!,
        topK: topK!,
        randomSeed: randomSeed,
      );
    }
  }

  /// Replaces the current session with one built from the given sampling
  /// parameters, swallowing failures. If no engine is installed the existing
  /// session is left untouched.
  static Future<void> recreateSession({
    required double temperature,
    required int topK,
  }) async {
    if (_engine == null) return;
    try {
      _session = await _engine!.createSession(
        temperature: temperature,
        topK: topK,
      );
    } catch (e) {
      debugPrint('Error recreating MediaPipe session: $e');
    }
  }

  /// Submits [prompt] to the current session and returns its response stream.
  ///
  /// The query chunk is added before this future completes, so callers control
  /// whether that work falls inside their timing window. Chunks are normalized
  /// to strings and empty chunks are filtered out.
  static Future<Stream<String>> generate(String prompt) async {
    final session = _session;
    if (session == null) {
      throw Exception('MediaPipe session is not initialized.');
    }

    await session.addQueryChunk(Message(text: prompt, isUser: true));

    final Stream<dynamic> raw = session.getResponseAsync();
    return raw
        .map<String>((chunk) => chunk?.toString() ?? '')
        .where((text) => text.isNotEmpty);
  }

  /// Drops the session and engine references so the native runtime can free
  /// its memory before another engine is loaded.
  static Future<void> release() async {
    _session = null;
    _engine = null;
  }
}