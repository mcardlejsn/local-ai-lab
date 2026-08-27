import 'package:flutter/services.dart';

typedef GgufDiscoverySeedTextLoader = Future<String> Function();

class GgufDiscoverySeedException implements Exception {
  const GgufDiscoverySeedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Loads the bounded, development-maintained bootstrap repository list.
///
/// Constructing this service reads nothing. The bundled asset is loaded only
/// when [loadRepositoryIds] is called from an explicit discovery request.
class GgufDiscoverySeedService {
  GgufDiscoverySeedService({
    GgufDiscoverySeedTextLoader? loadText,
    this.maximumRepositoryCount = 20,
  }) : _loadTextOverride = loadText;

  static const String assetPath = 'tools/model_candidate_repositories.txt';

  final GgufDiscoverySeedTextLoader? _loadTextOverride;
  final int maximumRepositoryCount;

  Future<List<String>> loadRepositoryIds() async {
    final String text;
    try {
      final GgufDiscoverySeedTextLoader? override = _loadTextOverride;
      text = override == null
          ? await rootBundle.loadString(assetPath)
          : await override();
    } on GgufDiscoverySeedException {
      rethrow;
    } catch (_) {
      throw const GgufDiscoverySeedException(
        'The bundled GGUF discovery seed list could not be loaded.',
      );
    }
    return parseRepositoryIds(
      text,
      maximumRepositoryCount: maximumRepositoryCount,
    );
  }

  static List<String> parseRepositoryIds(
    String text, {
    int maximumRepositoryCount = 20,
  }) {
    if (maximumRepositoryCount < 1) {
      throw ArgumentError.value(
        maximumRepositoryCount,
        'maximumRepositoryCount',
        'The maximum must be at least one.',
      );
    }

    final List<String> repositories = <String>[];
    final Set<String> seen = <String>{};
    final List<String> lines = text.split(RegExp(r'\r?\n'));
    final RegExp repositoryPattern = RegExp(r'^[^/\s]+/[^/\s]+$');

    for (int index = 0; index < lines.length; index++) {
      final String line = lines[index].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (!repositoryPattern.hasMatch(line)) {
        throw GgufDiscoverySeedException(
          'The bundled GGUF discovery seed list has an invalid repository '
          'on line ${index + 1}.',
        );
      }

      if (seen.add(line.toLowerCase())) repositories.add(line);
      if (repositories.length > maximumRepositoryCount) {
        throw GgufDiscoverySeedException(
          'The bundled GGUF discovery seed list exceeds the '
          '$maximumRepositoryCount-repository limit.',
        );
      }
    }

    return List<String>.unmodifiable(repositories);
  }
}
