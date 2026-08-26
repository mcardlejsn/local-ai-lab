import '../models/gguf_candidate_assessment.dart';
import '../models/gguf_discovery_result.dart';
import '../models/hugging_face_model_metadata.dart';
import 'gguf_candidate_screening_service.dart';
import 'hugging_face_discovery_service.dart';

/// Coordinates one explicit Hugging Face search and Local AI Lab screening.
///
/// Constructing this service performs no network activity. The source is
/// contacted only when [discover] is called. Repository metadata requests are
/// intentionally sequential, and linked upstream metadata is fetched only
/// when it is required to resolve an otherwise unusable license.
class GgufDiscoveryService {
  GgufDiscoveryService({
    HuggingFaceDiscoveryService? source,
    GgufCandidateScreeningService? screening,
  })  : _source = source ?? HuggingFaceDiscoveryService(),
        _screening = screening ?? const GgufCandidateScreeningService();

  final HuggingFaceDiscoveryService _source;
  final GgufCandidateScreeningService _screening;

  Future<GgufDiscoveryResult> discover({int limit = 20}) async {
    final List<HuggingFaceRepositorySummary> summaries =
        await _source.searchPublicGgufRepositories(limit: limit);
    final List<GgufCandidateAssessment> assessments =
        <GgufCandidateAssessment>[];
    final List<GgufDiscoverySourceFailure> sourceFailures =
        <GgufDiscoverySourceFailure>[];
    final Set<String> seenRepositories = <String>{};

    // A null value records a failed lookup so a shared upstream repository is
    // never requested repeatedly during the same discovery run.
    final Map<String, HuggingFaceRepositoryMetadata?> upstreamCache =
        <String, HuggingFaceRepositoryMetadata?>{};

    for (final HuggingFaceRepositorySummary summary in summaries) {
      final String repositoryKey = summary.id.toLowerCase();
      if (!seenRepositories.add(repositoryKey)) continue;

      final HuggingFaceRepositoryMetadata? metadata = await _getMetadata(
        summary.id,
        sourceFailures,
      );
      if (metadata == null) continue;

      final Map<String, HuggingFaceRepositoryMetadata> upstreamMetadata =
          <String, HuggingFaceRepositoryMetadata>{};
      if (_requiresUpstreamLicense(metadata)) {
        final String upstreamId = metadata.quantizedBaseModels.single;
        final String upstreamKey = upstreamId.toLowerCase();
        if (!upstreamCache.containsKey(upstreamKey)) {
          upstreamCache[upstreamKey] = await _getMetadata(
            upstreamId,
            sourceFailures,
            requestedForRepositoryId: metadata.id,
          );
        }

        final HuggingFaceRepositoryMetadata? upstream =
            upstreamCache[upstreamKey];
        if (upstream != null) {
          upstreamMetadata[upstreamId] = upstream;
        }
      }

      assessments.add(
        _screening.assess(
          metadata,
          upstreamMetadata: upstreamMetadata,
        ),
      );
    }

    return GgufDiscoveryResult(
      assessments: assessments,
      sourceFailures: sourceFailures,
    );
  }

  Future<HuggingFaceRepositoryMetadata?> _getMetadata(
    String repositoryId,
    List<GgufDiscoverySourceFailure> sourceFailures, {
    String? requestedForRepositoryId,
  }) async {
    try {
      return await _source.getRepositoryMetadata(repositoryId);
    } on HuggingFaceDiscoveryException catch (error) {
      sourceFailures.add(
        GgufDiscoverySourceFailure(
          repositoryId: repositoryId,
          requestedForRepositoryId: requestedForRepositoryId,
          message: error.message,
        ),
      );
      return null;
    } on ArgumentError catch (error) {
      sourceFailures.add(
        GgufDiscoverySourceFailure(
          repositoryId: repositoryId,
          requestedForRepositoryId: requestedForRepositoryId,
          message:
              error.message?.toString() ?? 'Invalid repository identifier.',
        ),
      );
      return null;
    }
  }

  bool _requiresUpstreamLicense(HuggingFaceRepositoryMetadata metadata) {
    if (metadata.quantizedBaseModels.length != 1) return false;
    final String? label = metadata.declaredLicenseLabel?.trim();
    if (label == null || label.isEmpty) return true;
    final String lower = label.toLowerCase();
    return lower == 'other' || lower == 'unknown';
  }
}
