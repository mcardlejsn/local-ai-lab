/// Platform-neutral runtime/chat profiles for approved LiteRT-LM artifacts.
enum LiteRtLmRuntimeProfile { general, qwen3 }

/// Platform-neutral identity for one exact LiteRT-LM model artifact.
class LiteRtLmModelArtifact {
  const LiteRtLmModelArtifact({
    required this.repository,
    required this.revision,
    required this.filename,
    required this.sizeBytes,
    required this.sha256,
    required this.license,
    required this.displayName,
    required this.contextTokens,
    required this.runtimeProfile,
    required this.isThinking,
  });

  final String repository;
  final String revision;
  final String filename;
  final int sizeBytes;
  final String sha256;
  final String license;
  final String displayName;
  final int contextTokens;
  final LiteRtLmRuntimeProfile runtimeProfile;
  final bool isThinking;

  String get identity =>
      'litertlm://$repository@$revision/$filename#sha256=$sha256';

  String get downloadUrl =>
      'https://huggingface.co/$repository/resolve/$revision/$filename';

  bool hasExpectedFilename(String candidate) => candidate == filename;

  bool matchesVerifiedIdentity({
    required String candidateFilename,
    required int candidateSizeBytes,
    required String candidateSha256,
  }) {
    return hasExpectedFilename(candidateFilename) &&
        candidateSizeBytes == sizeBytes &&
        candidateSha256.toLowerCase() == sha256;
  }
}

const LiteRtLmModelArtifact prototypeLiteRtLmArtifact = LiteRtLmModelArtifact(
  repository: 'litert-community/Qwen3-0.6B',
  revision: '8414150f2e9dcc82449bcc9c5abc404b399a4d06',
  filename: 'qwen3_0_6b_mixed_int4.litertlm',
  sizeBytes: 497664000,
  sha256: 'b1baab462f6be49d70eada79d715c2c52cd9ece0cad00bddf6a2c097d23498e9',
  license: 'Apache-2.0',
  displayName: 'Qwen3 0.6B (LiteRT-LM)',
  // Preserve the already-qualified runtime budget used by the prototype.
  contextTokens: 2048,
  runtimeProfile: LiteRtLmRuntimeProfile.qwen3,
  isThinking: false,
);

const LiteRtLmModelArtifact olmo2OneBInstructLiteRtLmArtifact =
    LiteRtLmModelArtifact(
      repository: 'litert-community/OLMo-2-1B-Instruct',
      revision: 'f94e362b82804bab977df6da9a63352598ca45cb',
      filename: 'OLMo-2-1B-Instruct_q4_block32_ekv4096.litertlm',
      sizeBytes: 931241056,
      sha256:
          '8d2457b54397731c5f451babb6bebfb9877545b4b070ac76914aab348fd954b0',
      license: 'Apache-2.0',
      displayName: 'OLMo 2 1B Instruct (LiteRT-LM)',
      contextTokens: 4096,
      runtimeProfile: LiteRtLmRuntimeProfile.general,
      isThinking: false,
    );

const List<LiteRtLmModelArtifact> approvedLiteRtLmArtifacts =
    <LiteRtLmModelArtifact>[
      prototypeLiteRtLmArtifact,
      olmo2OneBInstructLiteRtLmArtifact,
    ];

/// Returns the approved artifact with this exact filename, if one exists.
LiteRtLmModelArtifact? liteRtLmArtifactForFilename(String candidateFilename) {
  for (final LiteRtLmModelArtifact artifact in approvedLiteRtLmArtifacts) {
    if (artifact.hasExpectedFilename(candidateFilename)) return artifact;
  }
  return null;
}
