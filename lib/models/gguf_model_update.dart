import 'gguf_candidate_assessment.dart';

enum GgufModelUpdateStatus {
  upToDate,
  updateAvailable,
  localFileChanged,
  unavailable,
}

/// Read-only result of comparing one installed GGUF artifact with its source.
class GgufModelUpdateResult {
  const GgufModelUpdateResult({
    required this.status,
    required this.installedArtifact,
    required this.message,
    this.remoteArtifact,
  });

  final GgufModelUpdateStatus status;
  final GgufCandidateArtifact installedArtifact;
  final GgufCandidateArtifact? remoteArtifact;
  final String message;

  bool get hasUpdate => status == GgufModelUpdateStatus.updateAvailable;
}
