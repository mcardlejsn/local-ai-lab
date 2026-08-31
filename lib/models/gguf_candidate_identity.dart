import 'hugging_face_model_metadata.dart';

/// Returns whether two passing repositories identify the same underlying
/// model closely enough for Candidate deduplication.
///
/// A shared declared base-model ID is authoritative. When base metadata is
/// missing, a fallback is used only for repository names with a clear trailing
/// GGUF packaging suffix. Multiple-base repositories are never inferred.
bool areEquivalentGgufCandidates(
  HuggingFaceRepositoryMetadata left,
  HuggingFaceRepositoryMetadata right,
) {
  final List<String> leftBases = left.quantizedBaseModels;
  final List<String> rightBases = right.quantizedBaseModels;
  if (leftBases.length > 1 || rightBases.length > 1) return false;

  if (leftBases.length == 1 && rightBases.length == 1) {
    final String? leftBaseId = _normalizedDeclaredBaseId(leftBases.single);
    final String? rightBaseId = _normalizedDeclaredBaseId(rightBases.single);
    return leftBaseId != null && leftBaseId == rightBaseId;
  }

  final String? leftName = leftBases.length == 1
      ? _normalizedDeclaredBaseName(leftBases.single)
      : _inferredRepositoryModelName(left.id);
  final String? rightName = rightBases.length == 1
      ? _normalizedDeclaredBaseName(rightBases.single)
      : _inferredRepositoryModelName(right.id);
  return leftName != null && leftName == rightName;
}

String? _normalizedDeclaredBaseId(String repositoryId) {
  final String normalized = repositoryId.trim().toLowerCase();
  return normalized.isEmpty ? null : normalized;
}

String? _normalizedDeclaredBaseName(String repositoryId) {
  final String trimmed = repositoryId.trim();
  if (trimmed.isEmpty) return null;
  return _normalizedModelName(trimmed.split('/').last);
}

String? _inferredRepositoryModelName(String repositoryId) {
  final String repositoryName = repositoryId.trim().split('/').last;
  final Match? suffix = RegExp(
    r'(?:[-_. ]+gguf)$',
    caseSensitive: false,
  ).firstMatch(repositoryName);
  if (suffix == null) return null;
  return _normalizedModelName(repositoryName.substring(0, suffix.start));
}

String? _normalizedModelName(String value) {
  final String normalized = value.toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9]'),
    '',
  );
  return normalized.isEmpty ? null : normalized;
}
