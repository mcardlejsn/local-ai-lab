import '../models/gguf_candidate_assessment.dart';
import '../models/gguf_discovery_result.dart';
import '../models/hugging_face_model_metadata.dart';
import '../models/model_catalog.dart';
import 'gguf_candidate_screening_service.dart';
import 'gguf_discovery_seed_service.dart';
import 'hugging_face_discovery_service.dart';

typedef GgufSeedRepositoryLoader = Future<List<String>> Function();

/// Coordinates one explicit seed-assisted Hugging Face discovery request.
///
/// Constructing this service performs no asset read or network activity. Both
/// occur only when [discover] is called. Repository metadata requests are
/// intentionally sequential, and linked upstream metadata is fetched only
/// when it is required to resolve an otherwise unusable license.
class GgufDiscoveryService {
  GgufDiscoveryService({
    HuggingFaceDiscoveryService? source,
    GgufCandidateScreeningService? screening,
    GgufSeedRepositoryLoader? loadSeedRepositories,
    Iterable<CatalogModel>? verifiedCatalog,
  })  : _source = source ?? HuggingFaceDiscoveryService(),
        _screening = screening ?? const GgufCandidateScreeningService(),
        _loadSeedRepositories = loadSeedRepositories ??
            GgufDiscoverySeedService().loadRepositoryIds,
        _verifiedCatalog = List<CatalogModel>.unmodifiable(
          verifiedCatalog ?? kModelCatalog,
        );

  static const int _maximumLiveSearchLimit = 10;

  final HuggingFaceDiscoveryService _source;
  final GgufCandidateScreeningService _screening;
  final GgufSeedRepositoryLoader _loadSeedRepositories;
  final List<CatalogModel> _verifiedCatalog;

  Future<GgufDiscoveryResult> discover({int limit = 10}) async {
    if (limit < 1 || limit > _maximumLiveSearchLimit) {
      throw ArgumentError(
        'Live discovery limit must be between 1 and '
        '$_maximumLiveSearchLimit.',
      );
    }

    final List<String> seedRepositories = await _loadSeedRepositories();
    final List<HuggingFaceRepositorySummary> summaries =
        await _source.searchPublicGgufRepositories(limit: limit);
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

    for (final String repositoryId in seedRepositories) {
      addRepository(repositoryId);
    }
    for (final HuggingFaceRepositorySummary summary in summaries) {
      addRepository(summary.id);
    }

    // A null value records a failed lookup so a shared upstream repository is
    // never requested repeatedly during the same discovery run.
    final Map<String, HuggingFaceRepositoryMetadata?> upstreamCache =
        <String, HuggingFaceRepositoryMetadata?>{};

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
      assessments.add(assessment);
    }

    return excludeVerifiedArtifacts(
      GgufDiscoveryResult(
        assessments: assessments,
        sourceFailures: sourceFailures,
      ),
    );
  }

  /// Applies the same exact-artifact Verified exclusion to live or cached
  /// discovery results. This prevents a Candidate cached by an older app build
  /// from remaining unverified after that artifact enters the bundled catalog.
  GgufDiscoveryResult excludeVerifiedArtifacts(GgufDiscoveryResult result) {
    return GgufDiscoveryResult(
      assessments: result.assessments.where((assessment) {
        final GgufCandidateArtifact? artifact = assessment.artifact;
        return artifact == null || !_matchesVerifiedArtifact(artifact);
      }),
      sourceFailures: result.sourceFailures,
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

  bool _matchesVerifiedArtifact(GgufCandidateArtifact artifact) {
    for (final CatalogModel model in _verifiedCatalog) {
      final Uri? sourcePage = Uri.tryParse(model.sourcePage);
      if (sourcePage == null) continue;
      final String catalogRepository = sourcePage.pathSegments
          .where((String segment) => segment.isNotEmpty)
          .join('/');
      if (catalogRepository.toLowerCase() !=
          artifact.repositoryId.toLowerCase()) {
        continue;
      }
      if (model.fileName.toLowerCase() != artifact.fileName.toLowerCase()) {
        continue;
      }
      if (model.sizeBytes != artifact.sizeBytes) continue;
      if (model.sha256.toLowerCase() != artifact.sha256.toLowerCase()) {
        continue;
      }
      return true;
    }
    return false;
  }
}
