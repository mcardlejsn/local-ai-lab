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
  });

  final String repository;
  final String revision;
  final String filename;
  final int sizeBytes;
  final String sha256;
  final String license;
  final String displayName;
  final int contextTokens;

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
  contextTokens: 2048,
);
