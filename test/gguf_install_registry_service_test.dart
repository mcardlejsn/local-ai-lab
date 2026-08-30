import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/gguf_candidate_assessment.dart';
import 'package:local_ai_summarizer/models/gguf_compatibility_policy.dart';
import 'package:local_ai_summarizer/services/gguf_install_registry_service.dart';

void main() {
  late Directory temporaryDirectory;
  late GgufInstallRegistryService registry;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'gguf-install-registry-test-',
    );
    registry = GgufInstallRegistryService(
      directoryProvider: () async => temporaryDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('records and reloads exact downloaded artifact provenance', () async {
    final GgufCandidateArtifact artifact = _artifact();

    expect(await registry.record(artifact), isTrue);

    final GgufInstallRegistryService reloaded = GgufInstallRegistryService(
      directoryProvider: () async => temporaryDirectory,
    );
    final List<GgufCandidateArtifact> saved = await reloaded.load();
    expect(saved, hasLength(1));
    expect(saved.single.repositoryId, artifact.repositoryId);
    expect(saved.single.commitSha, artifact.commitSha);
    expect(saved.single.fileName, artifact.fileName);
    expect(saved.single.sizeBytes, artifact.sizeBytes);
    expect(saved.single.sha256, artifact.sha256);
  });

  test('replaces same filename and removes its provenance', () async {
    final GgufCandidateArtifact original = _artifact();
    final GgufCandidateArtifact replacement = _artifact(
      commitSha: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      sha256:
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    );

    expect(await registry.record(original), isTrue);
    expect(await registry.record(replacement), isTrue);
    final List<GgufCandidateArtifact> saved = await registry.load();
    expect(saved, hasLength(1));
    expect(saved.single.commitSha, replacement.commitSha);
    expect(saved.single.sha256, replacement.sha256);

    expect(await registry.remove(replacement.fileName), isTrue);
    expect(await registry.load(), isEmpty);
  });
}

GgufCandidateArtifact _artifact({
  String commitSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  String sha256 =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
}) {
  const String repository = 'Publisher/Model-1B-Instruct-GGUF';
  const String fileName = 'model-1b-instruct-q4_k_m.gguf';
  return GgufCandidateArtifact(
    repositoryId: repository,
    commitSha: commitSha,
    fileName: fileName,
    sizeBytes: 500000000,
    sha256: sha256,
    downloadUri: Uri.parse(
      'https://huggingface.co/$repository/resolve/$commitSha/$fileName',
    ),
    sourcePage: Uri.parse('https://huggingface.co/$repository'),
    license: 'Apache-2.0',
    licenseSourceRepository: repository,
    hasCustomLicense: false,
    modelFamily: 'Qwen/ChatML',
    promptFormat: PromptFormat.chatml,
  );
}
