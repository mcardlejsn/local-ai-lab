import '../models/gguf_candidate_assessment.dart';
import '../models/gguf_candidate_identity.dart';
import '../models/gguf_discovery_result.dart';
import '../models/hugging_face_model_metadata.dart';
import 'gguf_candidate_screening_service.dart';
import 'gguf_discovery_seed_service.dart';
import 'hugging_face_discovery_service.dart';

typedef GgufSeedRepositoryLoader = Future<List<String>> Function();

/// Coordinates one explicit live-first Hugging Face discovery request.
///
/// Constructing this service performs no asset read or network activity. Both
/// occur only when [discover] is called. Repository metadata requests are
/// intentionally sequential, and linked upstream metadata is fetched only
/// when it is required to resolve an otherwise unusable license. Maintained
/// repositories are evaluated after live results as bounded fallbacks.
class GgufDiscoveryService {
  GgufDiscoveryService({
    HuggingFaceDiscoveryService? source,
    GgufCandidateScreeningService? screening,
    GgufSeedRepositoryLoader? loadSeedRepositories,
  }) : _source = source ?? HuggingFaceDiscoveryService(),
       _screening = screening ?? const GgufCandidateScreeningService(),
       _loadSeedRepositories =
           loadSeedRepositories ?? GgufDiscoverySeedService().loadRepositoryIds;

  static const int _maximumLiveSearchLimit = 50;

  final HuggingFaceDiscoveryService _source;
  final GgufCandidateScreeningService _screening;
  final GgufSeedRepositoryLoader _loadSeedRepositories;

  Future<GgufDiscoveryResult> discover({int limit = 50}) async {
    if (limit < 1 || limit > _maximumLiveSearchLimit) {
      throw ArgumentError(
        'Live discovery limit must be between 1 and '
        '$_maximumLiveSearchLimit.',
      );
    }

    final List<String> seedRepositories = await _loadSeedRepositories();
    final List<HuggingFaceRepositorySummary> summaries = await _source
        .searchPublicGgufRepositories(limit: limit);
    final List<GgufCandidateAssessment> assessments =
        <GgufCandidateAssessment>[];
    final List<GgufDiscoverySourceFailure> sourceFailures =
        <GgufDiscoverySourceFailure>[];
    final List<String> repositories = <String>[];
    final Set<String> seenRepositories = <String>{};

    void addRepository(String repositoryId) {
      if (seenRepositories.add(repositoryId.toLowerCase())) {
        repositories.add(repositoryId);
      }
    }

    for (final HuggingFaceRepositorySummary summary in summaries) {
      addRepository(summary.id);
    }
    for (final String repositoryId in seedRepositories) {
      addRepository(repositoryId);
    }

    // A null value records a failed lookup so a shared upstream repository is
    // never requested repeatedly during the same discovery run.
    final Map<String, HuggingFaceRepositoryMetadata?> upstreamCache =
        <String, HuggingFaceRepositoryMetadata?>{};
    // Repositories are ordered with live results in popularity order, followed
    // by maintained fallbacks. Keep only the first passing artifact for an
    // equivalent underlying model.
    final List<HuggingFaceRepositoryMetadata> selectedModels =
        <HuggingFaceRepositoryMetadata>[];

    for (final String repositoryId in repositories) {
      final HuggingFaceRepositoryMetadata? metadata = await _getMetadata(
        repositoryId,
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

      final GgufCandidateAssessment assessment = _screening.assess(
        metadata,
        upstreamMetadata: upstreamMetadata,
      );
      if (!assessment.canDownload) continue;

      if (selectedModels.any(
        (selected) => areEquivalentGgufCandidates(selected, metadata),
      )) {
        continue;
      }
      selectedModels.add(metadata);
      assessments.add(assessment);
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
