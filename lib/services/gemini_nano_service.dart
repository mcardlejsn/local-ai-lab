import 'package:flutter/services.dart';

class GeminiNanoService {
  static const MethodChannel _channel =
      MethodChannel('com.mycarejournals.local_ai_summarizer/nano');

  static Future<bool> isAvailable() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('isNanoAvailable');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Version of the installed AICore package that serves Gemini Nano, as
  /// "versionName (versionCode)". Null if AICore is absent or unreadable.
  static Future<String?> getAiCoreVersion() async {
    try {
      return await _channel.invokeMethod<String>('getAiCoreVersion');
    } catch (_) {
      return null;
    }
  }

  static Future<String> generateText({
    required String prompt,
    double temperature = 0.20,
    int topK = 40,
  }) async {
    try {
      final String? result = await _channel.invokeMethod<String>(
        'generateNanoText',
        {
          'prompt': prompt,
          'temperature': temperature,
          'topK': topK,
        },
      );
      return result ?? '';
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Nano inference failed');
    }
  }
}