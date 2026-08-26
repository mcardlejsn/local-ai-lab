/// A repository returned by Hugging Face's model-search endpoint.
class HuggingFaceRepositorySummary {
  const HuggingFaceRepositorySummary({
    required this.id,
    required this.isPrivate,
    required this.gatedStatus,
    required this.tags,
    this.lastModified,
  });

  factory HuggingFaceRepositorySummary.fromJson(Map<String, dynamic> json) {
    return HuggingFaceRepositorySummary(
      id: _requiredString(json, 'id'),
      isPrivate: _requiredBool(json, 'private'),
      gatedStatus: _gatedStatus(json),
      tags: _requiredStringList(json, 'tags'),
      lastModified: _optionalDateTime(json['lastModified']),
    );
  }

  final String id;
  final bool isPrivate;

  /// Hugging Face reports `false` for ungated repositories and may report a
  /// boolean or a mode such as `auto` or `manual` for gated repositories.
  final String gatedStatus;
  final List<String> tags;
  final DateTime? lastModified;

  bool get isGated => gatedStatus != 'false';
  bool get isPublicAndUngated => !isPrivate && !isGated;
}

/// Exact metadata for one Hugging Face model repository revision.
class HuggingFaceRepositoryMetadata {
  const HuggingFaceRepositoryMetadata({
    required this.id,
    required this.commitSha,
    required this.isPrivate,
    required this.gatedStatus,
    required this.tags,
    required this.files,
    required this.quantizedBaseModels,
    this.license,
    this.licenseName,
    this.lastModified,
  });

  factory HuggingFaceRepositoryMetadata.fromJson(Map<String, dynamic> json) {
    final List<String> tags = _requiredStringList(json, 'tags');
    final Map<String, dynamic>? cardData = _optionalMap(json['cardData']);
    final String commitSha = _requiredString(json, 'sha').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(commitSha)) {
      throw const FormatException(
        'Hugging Face repository metadata has an invalid commit SHA.',
      );
    }

    final Object? siblingsValue = json['siblings'];
    if (siblingsValue is! List) {
      throw const FormatException(
        'Hugging Face repository metadata is missing its file list.',
      );
    }

    return HuggingFaceRepositoryMetadata(
      id: _requiredString(json, 'id'),
      commitSha: commitSha,
      isPrivate: _requiredBool(json, 'private'),
      gatedStatus: _gatedStatus(json),
      tags: tags,
      files: List<HuggingFaceRepositoryFile>.unmodifiable(
        siblingsValue.map((Object? value) {
          if (value is! Map) {
            throw const FormatException(
              'Hugging Face repository metadata contains an invalid file.',
            );
          }
          return HuggingFaceRepositoryFile.fromJson(
            Map<String, dynamic>.from(value),
          );
        }),
      ),
      quantizedBaseModels: List<String>.unmodifiable(
        _quantizedBaseModels(cardData: cardData, tags: tags),
      ),
      license: _optionalTrimmedString(cardData?['license']),
      licenseName: _optionalTrimmedString(cardData?['license_name']),
      lastModified: _optionalDateTime(json['lastModified']),
    );
  }

  final String id;
  final String commitSha;
  final bool isPrivate;
  final String gatedStatus;
  final List<String> tags;
  final List<HuggingFaceRepositoryFile> files;
  final List<String> quantizedBaseModels;
  final String? license;
  final String? licenseName;
  final DateTime? lastModified;

  bool get isGated => gatedStatus != 'false';
  bool get isPublicAndUngated => !isPrivate && !isGated;

  /// The most useful license label available directly from this repository.
  /// License inheritance from an upstream model remains a later policy step.
  String? get declaredLicenseLabel {
    final String? direct = license;
    if (direct == null) return null;
    if (direct.toLowerCase() == 'other' && licenseName != null) {
      return licenseName;
    }
    return direct;
  }
}

class HuggingFaceRepositoryFile {
  const HuggingFaceRepositoryFile({
    required this.path,
    this.sizeBytes,
    this.sha256,
  });

  factory HuggingFaceRepositoryFile.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic>? lfs = _optionalMap(json['lfs']);
    final String? sha256 =
        _optionalTrimmedString(lfs?['sha256'])?.toLowerCase();

    return HuggingFaceRepositoryFile(
      path: _requiredString(json, 'rfilename'),
      sizeBytes: _optionalPositiveInt(json['size'] ?? lfs?['size']),
      sha256: sha256 != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)
          ? sha256
          : null,
    );
  }

  final String path;
  final int? sizeBytes;
  final String? sha256;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final String? value = _optionalTrimmedString(json[key]);
  if (value == null) {
    throw FormatException('Hugging Face metadata is missing "$key".');
  }
  return value;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is! bool) {
    throw FormatException('Hugging Face metadata is missing boolean "$key".');
  }
  return value;
}

String _gatedStatus(Map<String, dynamic> json) {
  final Object? value = json['gated'];
  // Hugging Face's public API defines this field as optional and commonly
  // omits it for ordinary ungated repositories. Restricted repositories
  // report an explicit boolean or approval mode.
  if (value == null) return 'false';
  if (value is bool) return value ? 'true' : 'false';
  if (value is String && value.trim().isNotEmpty) {
    final String normalized = value.trim().toLowerCase();
    if (<String>{'false', 'true', 'auto', 'manual'}.contains(normalized)) {
      return normalized;
    }
  }
  throw const FormatException(
    'Hugging Face metadata contains an invalid gated status.',
  );
}

List<String> _requiredStringList(Map<String, dynamic> json, String key) {
  final Object? value = json[key];
  if (value is! List) {
    throw FormatException('Hugging Face metadata is missing list "$key".');
  }
  return List<String>.unmodifiable(value.map((Object? item) {
    if (item is! String || item.trim().isEmpty) {
      throw FormatException(
          'Hugging Face metadata has an invalid "$key" item.');
    }
    return item.trim();
  }));
}

Map<String, dynamic>? _optionalMap(Object? value) {
  if (value == null) return null;
  if (value is! Map) {
    throw const FormatException(
      'Hugging Face metadata contains an invalid object.',
    );
  }
  return Map<String, dynamic>.from(value);
}

String? _optionalTrimmedString(Object? value) {
  if (value is! String) return null;
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _optionalPositiveInt(Object? value) {
  final int? parsed = switch (value) {
    int number => number,
    num number => number.toInt(),
    String text => int.tryParse(text),
    _ => null,
  };
  return parsed != null && parsed > 0 ? parsed : null;
}

DateTime? _optionalDateTime(Object? value) {
  final String? text = _optionalTrimmedString(value);
  return text == null ? null : DateTime.tryParse(text);
}

Set<String> _quantizedBaseModels({
  required Map<String, dynamic>? cardData,
  required List<String> tags,
}) {
  final Set<String> repositories = <String>{};
  if (cardData != null) {
    final String? relation =
        _optionalTrimmedString(cardData['base_model_relation']);
    if (relation?.toLowerCase() == 'quantized') {
      final Object? baseModel = cardData['base_model'];
      final Iterable<Object?> candidates =
          baseModel is List ? baseModel : <Object?>[baseModel];
      for (final Object? candidate in candidates) {
        final String? repository = _repositoryId(candidate);
        if (repository != null) repositories.add(repository);
      }
    }
  }

  final RegExp tagPattern = RegExp(
    r'^base_model:quantized:([^/\s]+/[^/\s]+)$',
    caseSensitive: false,
  );
  for (final String tag in tags) {
    final RegExpMatch? match = tagPattern.firstMatch(tag);
    if (match != null) repositories.add(match.group(1)!);
  }
  return repositories;
}

String? _repositoryId(Object? value) {
  final String? text = _optionalTrimmedString(value)?.replaceAll(
    RegExp(r'^/+|/+$'),
    '',
  );
  if (text == null || !RegExp(r'^[^/\s]+/[^/\s]+$').hasMatch(text)) {
    return null;
  }
  return text;
}
