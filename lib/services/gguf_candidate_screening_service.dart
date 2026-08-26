import 'package:path/path.dart' as p;

import '../models/gguf_candidate_assessment.dart';
import '../models/gguf_compatibility_policy.dart';
import '../models/hugging_face_model_metadata.dart';

/// Applies Local AI Lab's mechanical discovery policy to already-fetched
/// Hugging Face metadata. It performs no network requests.
class GgufCandidateScreeningService {
  const GgufCandidateScreeningService({
    this.maximumSizeBytes = 3000000000,
  });

  final int maximumSizeBytes;

  GgufCandidateAssessment assess(
    HuggingFaceRepositoryMetadata metadata, {
    Map<String, HuggingFaceRepositoryMetadata> upstreamMetadata =
        const <String, HuggingFaceRepositoryMetadata>{},
  }) {
    final List<String> failures = <String>[];
    final List<String> reviewReasons = <String>[];
    final List<String> warnings = <String>[];

    if (!metadata.isPublicAndUngated) {
      failures.add('The repository is private or gated.');
    }

    final List<HuggingFaceRepositoryFile> q4Files = metadata.files
        .where((file) => _isQ4Km(file.path))
        .toList(growable: false);
    final List<HuggingFaceRepositoryFile> completeQ4Files =
        q4Files.where((file) => !_isShard(file.path)).toList(growable: false);

    final String identity = <String>[
      metadata.id,
      ...q4Files.map((file) => file.path),
    ].join(' ');
    if (_isExplicitBase(identity)) {
      failures.add('The repository or artifact is explicitly a Base model.');
    } else if (!_isInstructionTuned(identity, metadata.tags)) {
      reviewReasons.add(
        'The repository does not clearly identify Instruct, Chat, or IT tuning.',
      );
    }

    if (q4Files.isEmpty) {
      failures.add('No Q4_K_M GGUF artifact was found.');
    } else if (completeQ4Files.isEmpty) {
      failures.add('Q4_K_M is available only as split artifacts.');
    } else if (completeQ4Files.length > 1) {
      reviewReasons.add(
        'More than one complete Q4_K_M artifact is available.',
      );
    }

    final HuggingFaceRepositoryFile? selectedFile =
        completeQ4Files.length == 1 ? completeQ4Files.single : null;
    GgufCompatibilityAssessment? compatibility;
    if (selectedFile != null) {
      if (selectedFile.sizeBytes == null) {
        reviewReasons.add('The exact artifact size is unavailable.');
      } else if (selectedFile.sizeBytes! > maximumSizeBytes) {
        failures.add('The artifact exceeds the 3 GB discovery limit.');
      }
      if (selectedFile.sha256 == null) {
        reviewReasons.add('The artifact does not provide a valid SHA-256.');
      }

      compatibility = assessGgufCompatibility(selectedFile.path);
      if (compatibility.isKnownIncompatible) {
        failures.add(compatibility.explanation);
      } else if (!compatibility.discoveryEligible) {
        reviewReasons.add(compatibility.explanation);
      }
    }

    final _ResolvedLicense? resolvedLicense = _resolveLicense(
      metadata,
      upstreamMetadata,
      reviewReasons,
    );
    if (resolvedLicense?.isCustom ?? false) {
      warnings.add(
        'Custom license — review ${resolvedLicense!.label} terms before download.',
      );
    }

    final GgufCandidateDisposition disposition;
    if (failures.isNotEmpty) {
      disposition = GgufCandidateDisposition.rejected;
    } else if (reviewReasons.isNotEmpty) {
      disposition = GgufCandidateDisposition.needsReview;
    } else {
      disposition = GgufCandidateDisposition.candidate;
    }

    final List<String> reasons =
        disposition == GgufCandidateDisposition.rejected
            ? <String>[...failures, ...reviewReasons]
            : reviewReasons;
    final bool hasCompleteCandidateFacts =
        disposition == GgufCandidateDisposition.candidate &&
            selectedFile != null &&
            selectedFile.sizeBytes != null &&
            selectedFile.sha256 != null &&
            compatibility != null &&
            resolvedLicense != null;

    return GgufCandidateAssessment(
      repositoryId: metadata.id,
      disposition: disposition,
      reasons: List<String>.unmodifiable(reasons),
      warnings: List<String>.unmodifiable(warnings),
      artifact: hasCompleteCandidateFacts
          ? _buildArtifact(
              metadata: metadata,
              file: selectedFile,
              compatibility: compatibility,
              license: resolvedLicense,
            )
          : null,
    );
  }

  GgufCandidateArtifact _buildArtifact({
    required HuggingFaceRepositoryMetadata metadata,
    required HuggingFaceRepositoryFile file,
    required GgufCompatibilityAssessment compatibility,
    required _ResolvedLicense license,
  }) {
    final List<String> repositoryParts = metadata.id.split('/');
    final List<String> fileParts = file.path
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return GgufCandidateArtifact(
      repositoryId: metadata.id,
      commitSha: metadata.commitSha,
      // Keep repository subdirectories in the download URL, but never pass
      // them to the downloader as part of the local destination filename.
      fileName: p.posix.basename(file.path),
      sizeBytes: file.sizeBytes!,
      sha256: file.sha256!,
      downloadUri: Uri(
        scheme: 'https',
        host: 'huggingface.co',
        pathSegments: <String>[
          ...repositoryParts,
          'resolve',
          metadata.commitSha,
          ...fileParts,
        ],
      ),
      sourcePage: Uri(
        scheme: 'https',
        host: 'huggingface.co',
        pathSegments: repositoryParts,
      ),
      license: license.label,
      licenseSourceRepository: license.sourceRepository,
      hasCustomLicense: license.isCustom,
      modelFamily: compatibility.family,
      promptFormat: compatibility.promptFormat,
    );
  }

  _ResolvedLicense? _resolveLicense(
    HuggingFaceRepositoryMetadata metadata,
    Map<String, HuggingFaceRepositoryMetadata> upstreamMetadata,
    List<String> reviewReasons,
  ) {
    final String? direct = _usableLicense(metadata);
    if (direct != null) {
      return _ResolvedLicense(
        label: _normalizeLicense(direct),
        sourceRepository: metadata.id,
        isCustom: !_isPermissiveLicense(direct),
      );
    }

    if (metadata.quantizedBaseModels.isEmpty) {
      reviewReasons.add('The repository does not declare a usable license.');
      return null;
    }
    if (metadata.quantizedBaseModels.length > 1) {
      reviewReasons.add(
        'License inheritance is ambiguous across multiple upstream models.',
      );
      return null;
    }

    final String upstreamId = metadata.quantizedBaseModels.single;
    final HuggingFaceRepositoryMetadata? upstream =
        _findMetadata(upstreamId, upstreamMetadata);
    if (upstream == null) {
      reviewReasons.add(
        'License metadata must be retrieved from the linked upstream model.',
      );
      return null;
    }
    final String? inherited = _usableLicense(upstream);
    if (inherited == null) {
      reviewReasons.add(
        'The linked upstream model does not declare a usable license.',
      );
      return null;
    }
    return _ResolvedLicense(
      label: _normalizeLicense(inherited),
      sourceRepository: upstream.id,
      isCustom: !_isPermissiveLicense(inherited),
    );
  }

  HuggingFaceRepositoryMetadata? _findMetadata(
    String repositoryId,
    Map<String, HuggingFaceRepositoryMetadata> metadata,
  ) {
    final String wanted = repositoryId.toLowerCase();
    for (final entry in metadata.entries) {
      if (entry.key.toLowerCase() == wanted ||
          entry.value.id.toLowerCase() == wanted) {
        return entry.value;
      }
    }
    return null;
  }

  String? _usableLicense(HuggingFaceRepositoryMetadata metadata) {
    final String? label = metadata.declaredLicenseLabel?.trim();
    if (label == null || label.isEmpty) return null;
    final String lower = label.toLowerCase();
    if (lower == 'other' || lower == 'unknown') return null;
    return label;
  }

  bool _isPermissiveLicense(String license) {
    final String lower = license.toLowerCase();
    return lower == 'apache-2.0' || lower == 'mit';
  }

  String _normalizeLicense(String license) {
    switch (license.toLowerCase()) {
      case 'apache-2.0':
        return 'Apache-2.0';
      case 'mit':
        return 'MIT';
      case 'falcon-llm-license':
        return 'Falcon-LLM License';
      default:
        return license;
    }
  }

  bool _isQ4Km(String fileName) {
    return RegExp(r'q4_k_m.*\.gguf$', caseSensitive: false).hasMatch(fileName);
  }

  bool _isShard(String fileName) {
    return RegExp(
      r'-\d{5}-of-\d{5}\.gguf$',
      caseSensitive: false,
    ).hasMatch(fileName);
  }

  bool _isExplicitBase(String identity) {
    return RegExp(
      r'(?:^|[-_./ ])base(?:$|[-_./ ])',
      caseSensitive: false,
    ).hasMatch(identity);
  }

  bool _isInstructionTuned(String identity, List<String> tags) {
    if (tags.any((tag) => tag.toLowerCase() == 'conversational')) return true;
    return RegExp(
      r'(?:^|[-_./ ])(?:instruct(?:ion|ed)?|chat|it)(?:$|[-_./ ])',
      caseSensitive: false,
    ).hasMatch(identity);
  }
}

class _ResolvedLicense {
  const _ResolvedLicense({
    required this.label,
    required this.sourceRepository,
    required this.isCustom,
  });

  final String label;
  final String sourceRepository;
  final bool isCustom;
}
