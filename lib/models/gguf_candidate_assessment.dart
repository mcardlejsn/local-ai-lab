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

  /// Human-readable license name for Discovery and download confirmation.
  ///
  /// Cached discovery results may still contain Hugging Face license IDs, so
  /// this is derived at display time instead of changing the cache schema.
  String get licenseDisplayName {
    switch (license.trim().toLowerCase()) {
      case 'qwen-research':
      case 'qwen research license':
        return 'Qwen Research License';
      case 'llama3':
      case 'llama 3 community license':
        return 'Llama 3 Community License';
      case 'llama3.1':
      case 'llama 3.1 community license':
        return 'Llama 3.1 Community License';
      case 'llama3.2':
      case 'llama 3.2 community license':
        return 'Llama 3.2 Community License';
      case 'gemma':
      case 'gemma terms of use':
        return 'Gemma Terms of Use';
      case 'falcon-llm-license':
      case 'falcon-llm license':
        return 'Falcon-LLM License';
      default:
        return license;
    }
  }

  /// Best available public page for reviewing this license.
  ///
  /// Known licenses use their canonical terms. A usable license that does not
  /// yet have a direct mapping falls back to the repository that supplied the
  /// license metadata.
  Uri get licenseTermsUri {
    return _knownLicenseTermsUri ??
        Uri(
          scheme: 'https',
          host: 'huggingface.co',
          pathSegments: licenseSourceRepository
              .split('/')
              .where((String part) => part.isNotEmpty)
              .toList(growable: false),
        );
  }

  /// Consistent wording for direct terms and recorded license sources.
  String get licenseLinkLabel => 'View license information';

  Uri? get _knownLicenseTermsUri {
    switch (license.trim().toLowerCase()) {
      case 'apache-2.0':
        return Uri.parse('https://www.apache.org/licenses/LICENSE-2.0');
      case 'mit':
        return Uri.parse('https://opensource.org/license/mit');
      case 'qwen-research':
      case 'qwen research license':
        return Uri.parse(
          'https://huggingface.co/Qwen/Qwen2.5-3B/blob/main/LICENSE',
        );
      case 'llama3':
      case 'llama 3 community license':
        return Uri.parse('https://developer.meta.com/ai/llama3/license/');
      case 'llama3.1':
      case 'llama 3.1 community license':
        return Uri.parse('https://developer.meta.com/ai/llama3_1/license/');
      case 'llama3.2':
      case 'llama 3.2 community license':
        return Uri.parse('https://developer.meta.com/ai/llama3_2/license/');
      case 'gemma':
      case 'gemma terms of use':
        return Uri.parse('https://ai.google.dev/gemma/terms');
      default:
        return null;
    }
  }

  /// Stable identity for qualification history.
  ///
  /// Repository, commit, filename, and digest together prevent a benchmark
  /// for an older same-named file from qualifying different bytes later.
  String get qualificationArtifactId =>
      '$repositoryId@${commitSha.toLowerCase()}/$fileName#'
      '${sha256.toLowerCase()}';
}
