import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/gguf_candidate_assessment.dart';
import '../models/gguf_model_update.dart';
import '../models/hugging_face_model_metadata.dart';
import 'gguf_candidate_screening_service.dart';
import 'hugging_face_discovery_service.dart';

abstract interface class GgufModelUpdateChecker {
  Future<GgufCandidateArtifact?> recognizeInstalledArtifact({
    required String installedPath,
    required Iterable<GgufCandidateArtifact> candidates,
  });

  Future<GgufModelUpdateResult> check({
    required GgufCandidateArtifact installedArtifact,
    required String installedPath,
    bool localIdentityAlreadyVerified = false,
  });
}

/// Performs one explicit, read-only GGUF update comparison.
class GgufModelUpdateService implements GgufModelUpdateChecker {
  GgufModelUpdateService({
    HuggingFaceDiscoveryService? source,
    GgufCandidateScreeningService? screening,
  }) : _source = source ?? HuggingFaceDiscoveryService(),
       _screening = screening ?? const GgufCandidateScreeningService();

  final HuggingFaceDiscoveryService _source;
  final GgufCandidateScreeningService _screening;

  @override
  Future<GgufCandidateArtifact?> recognizeInstalledArtifact({
    required String installedPath,
    required Iterable<GgufCandidateArtifact> candidates,
  }) async {
    final File file = File(installedPath);
    if (!await file.exists()) return null;
    final int size = await file.length();
    final String fileName = p.basename(installedPath).toLowerCase();
    final List<GgufCandidateArtifact> possible = candidates
        .where(
          (GgufCandidateArtifact artifact) =>
              artifact.fileName.toLowerCase() == fileName &&
              artifact.sizeBytes == size,
        )
        .toList(growable: false);
    if (possible.isEmpty) return null;
    final String digest = await _sha256OfFile(file);
    for (final GgufCandidateArtifact artifact in possible) {
      if (artifact.sha256.toLowerCase() == digest) return artifact;
    }
    return null;
  }

  @override
  Future<GgufModelUpdateResult> check({
    required GgufCandidateArtifact installedArtifact,
    required String installedPath,
    bool localIdentityAlreadyVerified = false,
  }) async {
    try {
      if (!localIdentityAlreadyVerified) {
        final GgufCandidateArtifact? matched = await recognizeInstalledArtifact(
          installedPath: installedPath,
          candidates: <GgufCandidateArtifact>[installedArtifact],
        );
        if (matched == null) {
          return GgufModelUpdateResult(
            status: GgufModelUpdateStatus.localFileChanged,
            installedArtifact: installedArtifact,
            message:
                'The installed file no longer matches its saved size and '
                'SHA-256.',
          );
        }
      }

      final HuggingFaceRepositoryMetadata metadata = await _source
          .getRepositoryMetadata(installedArtifact.repositoryId);
      final Map<String, HuggingFaceRepositoryMetadata> upstream =
          <String, HuggingFaceRepositoryMetadata>{};
      if (_requiresUpstreamLicense(metadata)) {
        final String upstreamId = metadata.quantizedBaseModels.single;
        upstream[upstreamId] = await _source.getRepositoryMetadata(upstreamId);
      }

      final GgufCandidateAssessment assessment = _screening.assess(
        metadata,
        upstreamMetadata: upstream,
      );
      final GgufCandidateArtifact? remote = assessment.artifact;
      if (!assessment.canDownload || remote == null) {
        return GgufModelUpdateResult(
          status: GgufModelUpdateStatus.unavailable,
          installedArtifact: installedArtifact,
          message:
              'The source no longer exposes one update-eligible Q4_K_M '
              'artifact.',
        );
      }

      if (remote.sha256.toLowerCase() ==
          installedArtifact.sha256.toLowerCase()) {
        return GgufModelUpdateResult(
          status: GgufModelUpdateStatus.upToDate,
          installedArtifact: installedArtifact,
          remoteArtifact: remote,
          message: 'The installed artifact matches the current remote bytes.',
        );
      }
      return GgufModelUpdateResult(
        status: GgufModelUpdateStatus.updateAvailable,
        installedArtifact: installedArtifact,
        remoteArtifact: remote,
        message: 'The current remote artifact has a different SHA-256.',
      );
    } on HuggingFaceDiscoveryException catch (error) {
      return GgufModelUpdateResult(
        status: GgufModelUpdateStatus.unavailable,
        installedArtifact: installedArtifact,
        message: error.message,
      );
    } on ArgumentError catch (error) {
      return GgufModelUpdateResult(
        status: GgufModelUpdateStatus.unavailable,
        installedArtifact: installedArtifact,
        message: error.message?.toString() ?? 'Invalid repository identity.',
      );
    } on FileSystemException catch (error) {
      return GgufModelUpdateResult(
        status: GgufModelUpdateStatus.localFileChanged,
        installedArtifact: installedArtifact,
        message: error.message,
      );
    }
  }

  bool _requiresUpstreamLicense(HuggingFaceRepositoryMetadata metadata) {
    if (metadata.quantizedBaseModels.length != 1) return false;
    final String? label = metadata.declaredLicenseLabel?.trim();
    if (label == null || label.isEmpty) return true;
    final String lower = label.toLowerCase();
    return lower == 'other' || lower == 'unknown';
  }

  Future<String> _sha256OfFile(File file) {
    final String filePath = file.path;
    return Isolate.run(() async {
      final Digest digest = await sha256.bind(File(filePath).openRead()).first;
      return digest.toString().toLowerCase();
    });
  }
}
