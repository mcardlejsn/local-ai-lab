import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/gguf_candidate_assessment.dart';
import '../models/gguf_compatibility_policy.dart';
import '../models/gguf_discovery_result.dart';

typedef GgufDiscoveryCacheDirectoryProvider = Future<Directory> Function();

abstract interface class GgufDiscoveryCache {
  Future<GgufDiscoveryCacheEntry?> load();

  Future<bool> save(
    GgufDiscoveryResult result, {
    required DateTime discoveredAtUtc,
  });
}

class GgufDiscoveryCacheEntry {
  const GgufDiscoveryCacheEntry({
    required this.result,
    required this.discoveredAtUtc,
  });

  final GgufDiscoveryResult result;
  final DateTime discoveredAtUtc;
}

/// Stores the last successful Candidate-only discovery snapshot locally.
///
/// Loading and saving this cache never performs a network request. Invalid or
/// unreadable cache data is ignored so the user can always run Discover again.
class GgufDiscoveryCacheService implements GgufDiscoveryCache {
  GgufDiscoveryCacheService({
    GgufDiscoveryCacheDirectoryProvider? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const int _schemaVersion = 1;
  static const String _cacheFileName = 'gguf_discovery_cache_v1.json';

  final GgufDiscoveryCacheDirectoryProvider _directoryProvider;

  @override
  Future<GgufDiscoveryCacheEntry?> load() async {
    try {
      final File file = await _cacheFile();
      if (!await file.exists()) return null;

      final Object? decoded = jsonDecode(await file.readAsString());
      final Map<String, Object?> root = _objectMap(decoded);
      if (_requiredInt(root, 'schemaVersion') != _schemaVersion) return null;

      final DateTime discoveredAtUtc =
          DateTime.parse(_requiredString(root, 'discoveredAtUtc')).toUtc();
      final Map<String, Object?> resultJson = _objectMap(root['result']);

      final List<GgufCandidateAssessment> assessments =
          _objectList(resultJson, 'assessments')
              .map(_assessmentFromJson)
              .toList(growable: false);
      final List<GgufDiscoverySourceFailure> sourceFailures =
          _objectList(resultJson, 'sourceFailures')
              .map(_sourceFailureFromJson)
              .toList(growable: false);

      return GgufDiscoveryCacheEntry(
        result: GgufDiscoveryResult(
          assessments: assessments,
          sourceFailures: sourceFailures,
        ),
        discoveredAtUtc: discoveredAtUtc,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> save(
    GgufDiscoveryResult result, {
    required DateTime discoveredAtUtc,
  }) async {
    File? temporaryFile;
    try {
      final File cacheFile = await _cacheFile();
      await cacheFile.parent.create(recursive: true);
      temporaryFile = File('${cacheFile.path}.tmp');

      final List<GgufCandidateAssessment> downloadableCandidates = result
          .assessments
          .where((assessment) => assessment.canDownload)
          .toList(growable: false);
      final Map<String, Object?> payload = <String, Object?>{
        'schemaVersion': _schemaVersion,
        'discoveredAtUtc': discoveredAtUtc.toUtc().toIso8601String(),
        'result': <String, Object?>{
          'assessments': downloadableCandidates
              .map(_assessmentToJson)
              .toList(growable: false),
          'sourceFailures': result.sourceFailures
              .map(_sourceFailureToJson)
              .toList(growable: false),
        },
      };

      await temporaryFile.writeAsString(jsonEncode(payload), flush: true);
      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }
      await temporaryFile.rename(cacheFile.path);
      return true;
    } on Object {
      try {
        if (temporaryFile != null && await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
      } on Object {
        // A failed cleanup must not turn an optional cache into an app error.
      }
      return false;
    }
  }

  Future<File> _cacheFile() async {
    final Directory directory = await _directoryProvider();
    return File(p.join(directory.path, _cacheFileName));
  }
}

Map<String, Object?> _assessmentToJson(
  GgufCandidateAssessment assessment,
) {
  final GgufCandidateArtifact artifact = assessment.artifact!;
  return <String, Object?>{
    'repositoryId': assessment.repositoryId,
    'disposition': assessment.disposition.name,
    'reasons': assessment.reasons,
    'warnings': assessment.warnings,
    'artifact': <String, Object?>{
      'repositoryId': artifact.repositoryId,
      'commitSha': artifact.commitSha,
      'fileName': artifact.fileName,
      'sizeBytes': artifact.sizeBytes,
      'sha256': artifact.sha256,
      'downloadUri': artifact.downloadUri.toString(),
      'sourcePage': artifact.sourcePage.toString(),
      'license': artifact.license,
      'licenseSourceRepository': artifact.licenseSourceRepository,
      'hasCustomLicense': artifact.hasCustomLicense,
      'modelFamily': artifact.modelFamily,
      'promptFormat': artifact.promptFormat.name,
    },
  };
}

GgufCandidateAssessment _assessmentFromJson(Object? value) {
  final Map<String, Object?> json = _objectMap(value);
  final GgufCandidateDisposition disposition =
      _enumByName(GgufCandidateDisposition.values, json, 'disposition');
  if (disposition != GgufCandidateDisposition.candidate) {
    throw const FormatException('Cached assessment is not a Candidate.');
  }

  final Map<String, Object?> artifactJson = _objectMap(json['artifact']);
  final String repositoryId = _requiredString(json, 'repositoryId');
  final String artifactRepositoryId =
      _requiredString(artifactJson, 'repositoryId');
  if (repositoryId != artifactRepositoryId) {
    throw const FormatException('Cached repository identity does not match.');
  }

  final GgufCandidateArtifact artifact = GgufCandidateArtifact(
    repositoryId: artifactRepositoryId,
    commitSha: _requiredString(artifactJson, 'commitSha'),
    fileName: _requiredString(artifactJson, 'fileName'),
    sizeBytes: _requiredInt(artifactJson, 'sizeBytes'),
    sha256: _requiredString(artifactJson, 'sha256'),
    downloadUri: Uri.parse(_requiredString(artifactJson, 'downloadUri')),
    sourcePage: Uri.parse(_requiredString(artifactJson, 'sourcePage')),
    license: _requiredString(artifactJson, 'license'),
    licenseSourceRepository:
        _requiredString(artifactJson, 'licenseSourceRepository'),
    hasCustomLicense: _requiredBool(artifactJson, 'hasCustomLicense'),
    modelFamily: _requiredString(artifactJson, 'modelFamily'),
    promptFormat:
        _enumByName(PromptFormat.values, artifactJson, 'promptFormat'),
  );

  return GgufCandidateAssessment(
    repositoryId: repositoryId,
    disposition: disposition,
    reasons: _stringList(json, 'reasons'),
    warnings: _stringList(json, 'warnings'),
    artifact: artifact,
  );
}

Map<String, Object?> _sourceFailureToJson(
  GgufDiscoverySourceFailure failure,
) {
  return <String, Object?>{
    'repositoryId': failure.repositoryId,
    'requestedForRepositoryId': failure.requestedForRepositoryId,
    'message': failure.message,
  };
}

GgufDiscoverySourceFailure _sourceFailureFromJson(Object? value) {
  final Map<String, Object?> json = _objectMap(value);
  final Object? requestedValue = json['requestedForRepositoryId'];
  final String? requestedForRepositoryId;
  if (requestedValue == null) {
    requestedForRepositoryId = null;
  } else if (requestedValue is String) {
    requestedForRepositoryId = requestedValue;
  } else {
    throw const FormatException('Invalid cached source failure.');
  }
  return GgufDiscoverySourceFailure(
    repositoryId: _requiredString(json, 'repositoryId'),
    requestedForRepositoryId: requestedForRepositoryId,
    message: _requiredString(json, 'message'),
  );
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map<Object?, Object?>) {
    throw const FormatException('Expected an object.');
  }
  return value.map<String, Object?>((Object? key, Object? item) {
    if (key is! String) throw const FormatException('Expected a string key.');
    return MapEntry<String, Object?>(key, item);
  });
}

List<Object?> _objectList(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! List) throw FormatException('Expected a list for $key.');
  return value.cast<Object?>();
}

List<String> _stringList(Map<String, Object?> json, String key) {
  final List<Object?> values = _objectList(json, key);
  if (values.any((Object? value) => value is! String)) {
    throw FormatException('Expected strings for $key.');
  }
  return List<String>.unmodifiable(values.cast<String>());
}

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Expected a non-empty string for $key.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! int) throw FormatException('Expected an integer for $key.');
  return value;
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! bool) throw FormatException('Expected a boolean for $key.');
  return value;
}

T _enumByName<T extends Enum>(
  Iterable<T> values,
  Map<String, Object?> json,
  String key,
) {
  final String name = _requiredString(json, key);
  return values.firstWhere(
    (T value) => value.name == name,
    orElse: () => throw FormatException('Unknown value for $key.'),
  );
}
