import 'gguf_candidate_assessment.dart';

/// The user-facing outcome of one explicit in-app discovery request.
///
/// [assessments] contains only downloadable Candidates. Needs-review and
/// rejected repositories are still screened but are not returned as model
/// results. Source failures remain available for tests and diagnostics, but
/// are not presented as model results on the discovery screen.
class GgufDiscoveryResult {
  GgufDiscoveryResult({
    required Iterable<GgufCandidateAssessment> assessments,
    required Iterable<GgufDiscoverySourceFailure> sourceFailures,
  })  : assessments = List<GgufCandidateAssessment>.unmodifiable(assessments),
        sourceFailures =
            List<GgufDiscoverySourceFailure>.unmodifiable(sourceFailures);

  final List<GgufCandidateAssessment> assessments;
  final List<GgufDiscoverySourceFailure> sourceFailures;

  int get candidateCount => assessments.length;
}

/// A repository metadata request that could not be completed during discovery.
class GgufDiscoverySourceFailure {
  const GgufDiscoverySourceFailure({
    required this.repositoryId,
    required this.message,
    this.requestedForRepositoryId,
  });

  /// The repository whose metadata request failed.
  final String repositoryId;

  /// The candidate repository that required this request when it was an
  /// upstream-license lookup. Null for a failed candidate-detail request.
  final String? requestedForRepositoryId;

  final String message;
}
