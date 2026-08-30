import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/gguf_candidate_assessment.dart';
import '../models/gguf_compatibility_policy.dart';

typedef GgufInstallRegistryDirectoryProvider = Future<Directory> Function();

abstract interface class GgufInstallRegistry {
  Future<List<GgufCandidateArtifact>> load();

  Future<bool> record(GgufCandidateArtifact artifact);

  Future<bool> remove(String fileName);
}

/// Persists source identity only for GGUF artifacts installed by Local AI Lab.
///
/// This registry is separate from the replaceable Discovery cache. It performs
/// no network requests and never modifies model files.
class GgufInstallRegistryService implements GgufInstallRegistry {
  GgufInstallRegistryService({
    GgufInstallRegistryDirectoryProvider? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const int _schemaVersion = 1;
  static const String _fileName = 'gguf_install_registry_v1.json';

  final GgufInstallRegistryDirectoryProvider _directoryProvider;

  @override
  Future<List<GgufCandidateArtifact>> load() async {
    try {
      final File file = await _registryFile();
      if (!await file.exists()) return const <GgufCandidateArtifact>[];
      final Object? decoded = jsonDecode(await file.readAsString());
      final Map<String, Object?> root = _objectMap(decoded);
      if (_requiredInt(root, 'schemaVersion') != _schemaVersion) {
        return const <GgufCandidateArtifact>[];
      }
      final Object? artifactsValue = root['artifacts'];
      if (artifactsValue is! List) {
        throw const FormatException('Expected an artifact list.');
      }
      return List<GgufCandidateArtifact>.unmodifiable(
        artifactsValue.map(_artifactFromJson),
      );
    } on Object {
      return const <GgufCandidateArtifact>[];
    }
  }

  @override
  Future<bool> record(GgufCandidateArtifact artifact) async {
    final List<GgufCandidateArtifact> artifacts = List.of(await load());
    final String wanted = artifact.fileName.toLowerCase();
    artifacts.removeWhere(
      (GgufCandidateArtifact saved) => saved.fileName.toLowerCase() == wanted,
    );
    artifacts.add(artifact);
    artifacts.sort(
      (GgufCandidateArtifact left, GgufCandidateArtifact right) =>
          left.fileName.toLowerCase().compareTo(right.fileName.toLowerCase()),
    );
    return _write(artifacts);
  }

  @override
  Future<bool> remove(String fileName) async {
    final List<GgufCandidateArtifact> artifacts = List.of(await load());
    final int originalLength = artifacts.length;
    final String wanted = fileName.toLowerCase();
    artifacts.removeWhere(
      (GgufCandidateArtifact saved) => saved.fileName.toLowerCase() == wanted,
    );
    if (artifacts.length == originalLength) return true;
    return _write(artifacts);
  }

  Future<bool> _write(List<GgufCandidateArtifact> artifacts) async {
    File? temporaryFile;
    try {
      final File registryFile = await _registryFile();
      await registryFile.parent.create(recursive: true);
      temporaryFile = File('${registryFile.path}.tmp');
      final Map<String, Object?> payload = <String, Object?>{
        'schemaVersion': _schemaVersion,
        'artifacts': artifacts.map(_artifactToJson).toList(growable: false),
      };
      await temporaryFile.writeAsString(jsonEncode(payload), flush: true);
      if (await registryFile.exists()) await registryFile.delete();
      await temporaryFile.rename(registryFile.path);
      return true;
    } on Object {
      try {
        if (temporaryFile != null && await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
      } on Object {
        // Registry persistence failure is reported by the false return value.
      }
      return false;
    }
  }

  Future<File> _registryFile() async {
    final Directory directory = await _directoryProvider();
    return File(p.join(directory.path, _fileName));
  }
}

Map<String, Object?> _artifactToJson(GgufCandidateArtifact artifact) {
  return <String, Object?>{
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
  };
}

GgufCandidateArtifact _artifactFromJson(Object? value) {
  final Map<String, Object?> json = _objectMap(value);
  return GgufCandidateArtifact(
    repositoryId: _requiredString(json, 'repositoryId'),
    commitSha: _requiredString(json, 'commitSha'),
    fileName: _requiredString(json, 'fileName'),
    sizeBytes: _requiredInt(json, 'sizeBytes'),
    sha256: _requiredString(json, 'sha256'),
    downloadUri: Uri.parse(_requiredString(json, 'downloadUri')),
    sourcePage: Uri.parse(_requiredString(json, 'sourcePage')),
    license: _requiredString(json, 'license'),
    licenseSourceRepository: _requiredString(json, 'licenseSourceRepository'),
    hasCustomLicense: _requiredBool(json, 'hasCustomLicense'),
    modelFamily: _requiredString(json, 'modelFamily'),
    promptFormat: PromptFormat.values.firstWhere(
      (PromptFormat format) =>
          format.name == _requiredString(json, 'promptFormat'),
    ),
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

String _requiredString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Expected a non-empty string for $key.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! int || value <= 0) {
    throw FormatException('Expected a positive integer for $key.');
  }
  return value;
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is! bool) throw FormatException('Expected a boolean for $key.');
  return value;
}
