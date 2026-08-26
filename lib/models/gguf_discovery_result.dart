import 'gguf_candidate_assessment.dart';

/// The complete outcome of one explicit in-app discovery request.
///
/// Assessments retain Candidate, Needs review, and Rejected outcomes so a
/// later UI can decide what to display without weakening the screening policy.
/// Source failures are kept separately because unavailable metadata is not a
/// compatibility judgment about the model itself.
class GgufDiscoveryResult {
  GgufDiscoveryResult({
    required Iterable<GgufCandidateAssessment> assessments,
    required Iterable<GgufDiscoverySourceFailure> sourceFailures,
  })  : assessments = List<GgufCandidateAssessment>.unmodifiable(assessments),
        sourceFailures =
            List<GgufDiscoverySourceFailure>.unmodifiable(sourceFailures);

  final List<GgufCandidateAssessment> assessments;
  final List<GgufDiscoverySourceFailure> sourceFailures;

  int get candidateCount => _count(GgufCandidateDisposition.candidate);
  int get needsReviewCount => _count(GgufCandidateDisposition.needsReview);
  int get rejectedCount => _count(GgufCandidateDisposition.rejected);

  int _count(GgufCandidateDisposition disposition) {
    return assessments
        .where((assessment) => assessment.disposition == disposition)
        .length;
  }
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
