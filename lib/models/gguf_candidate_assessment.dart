import 'gguf_compatibility_policy.dart';

enum GgufCandidateDisposition { candidate, needsReview, rejected }

class GgufCandidateAssessment {
  const GgufCandidateAssessment({
    required this.repositoryId,
    required this.disposition,
    required this.reasons,
    required this.warnings,
    this.artifact,
  });

  final String repositoryId;
  final GgufCandidateDisposition disposition;

  /// Facts that caused Needs review or Rejected. Empty for a Candidate.
  final List<String> reasons;

  /// Important information that does not prevent candidate download.
  final List<String> warnings;
  final GgufCandidateArtifact? artifact;

  bool get canDownload =>
      disposition == GgufCandidateDisposition.candidate && artifact != null;
}

class GgufCandidateArtifact {
  const GgufCandidateArtifact({
    required this.repositoryId,
    required this.commitSha,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    required this.downloadUri,
    required this.sourcePage,
    required this.license,
    required this.licenseSourceRepository,
    required this.hasCustomLicense,
    required this.modelFamily,
    required this.promptFormat,
  });

  final String repositoryId;
  final String commitSha;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final Uri downloadUri;
  final Uri sourcePage;
  final String license;
  final String licenseSourceRepository;
  final bool hasCustomLicense;
  final String modelFamily;
  final PromptFormat promptFormat;
}
