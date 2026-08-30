import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/models/gguf_candidate_assessment.dart';
import 'package:local_ai_summarizer/models/gguf_compatibility_policy.dart';
import 'package:local_ai_summarizer/models/gguf_model_update.dart';
import 'package:local_ai_summarizer/services/gguf_model_update_service.dart';
import 'package:local_ai_summarizer/services/hugging_face_discovery_service.dart';

void main() {
  late Directory temporaryDirectory;
  late File installedFile;
  late List<int> installedBytes;
  late String installedSha256;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'gguf-model-update-test-',
    );
    installedBytes = utf8.encode('installed model bytes');
    installedSha256 = sha256.convert(installedBytes).toString();
    installedFile = File(
      '${temporaryDirectory.path}/qwen2.5-1b-instruct-q4_k_m.gguf',
    );
    await installedFile.writeAsBytes(installedBytes);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('a changed repository commit alone is not an update', () async {
    final GgufModelUpdateService service = _service(
      remoteSha256: installedSha256,
      remoteSize: installedBytes.length,
    );

    final GgufModelUpdateResult result = await service.check(
      installedArtifact: _installedArtifact(
        sha256Value: installedSha256,
        sizeBytes: installedBytes.length,
      ),
      installedPath: installedFile.path,
    );

    expect(result.status, GgufModelUpdateStatus.upToDate);
    expect(result.remoteArtifact?.commitSha, _remoteCommit);
  });

  test('different remote SHA-256 produces a read-only update', () async {
    final List<int> remoteBytes = utf8.encode('new remote model bytes');
    final String remoteSha = sha256.convert(remoteBytes).toString();
    final GgufModelUpdateService service = _service(
      remoteSha256: remoteSha,
      remoteSize: remoteBytes.length,
    );

    final GgufModelUpdateResult result = await service.check(
      installedArtifact: _installedArtifact(
        sha256Value: installedSha256,
        sizeBytes: installedBytes.length,
      ),
      installedPath: installedFile.path,
    );

    expect(result.status, GgufModelUpdateStatus.updateAvailable);
    expect(result.remoteArtifact?.sha256, remoteSha);
    expect(result.installedArtifact.sha256, installedSha256);
  });

  test('changed local bytes block the remote check', () async {
    int requests = 0;
    final GgufModelUpdateService service = GgufModelUpdateService(
      source: HuggingFaceDiscoveryService(
        fetchJson: (Uri uri) async {
          requests++;
          return _remoteRepository(
            sha256Value: installedSha256,
            sizeBytes: installedBytes.length,
          );
        },
      ),
    );
    await installedFile.writeAsString('different local bytes');

    final GgufModelUpdateResult result = await service.check(
      installedArtifact: _installedArtifact(
        sha256Value: installedSha256,
        sizeBytes: installedBytes.length,
      ),
      installedPath: installedFile.path,
    );

    expect(result.status, GgufModelUpdateStatus.localFileChanged);
    expect(requests, 0);
  });

  test('recognizes an existing exact artifact from Candidate cache', () async {
    final GgufModelUpdateService service = _service(
      remoteSha256: installedSha256,
      remoteSize: installedBytes.length,
    );
    final GgufCandidateArtifact expected = _installedArtifact(
      sha256Value: installedSha256,
      sizeBytes: installedBytes.length,
    );

    final GgufCandidateArtifact?
    recognized = await service.recognizeInstalledArtifact(
      installedPath: installedFile.path,
      candidates: <GgufCandidateArtifact>[
        _installedArtifact(
          sha256Value:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          sizeBytes: installedBytes.length,
        ),
        expected,
      ],
    );

    expect(recognized, same(expected));
  });
}

const String _repository = 'Publisher/Model-1B-Instruct-GGUF';
const String _fileName = 'qwen2.5-1b-instruct-q4_k_m.gguf';
const String _installedCommit = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _remoteCommit = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

GgufModelUpdateService _service({
  required String remoteSha256,
  required int remoteSize,
}) {
  return GgufModelUpdateService(
    source: HuggingFaceDiscoveryService(
      fetchJson: (Uri uri) async =>
          _remoteRepository(sha256Value: remoteSha256, sizeBytes: remoteSize),
    ),
  );
}

GgufCandidateArtifact _installedArtifact({
  required String sha256Value,
  required int sizeBytes,
}) {
  return GgufCandidateArtifact(
    repositoryId: _repository,
    commitSha: _installedCommit,
    fileName: _fileName,
    sizeBytes: sizeBytes,
    sha256: sha256Value,
    downloadUri: Uri.parse(
      'https://huggingface.co/$_repository/resolve/'
      '$_installedCommit/$_fileName',
    ),
    sourcePage: Uri.parse('https://huggingface.co/$_repository'),
    license: 'Apache-2.0',
    licenseSourceRepository: _repository,
    hasCustomLicense: false,
    modelFamily: 'Qwen/ChatML',
    promptFormat: PromptFormat.chatml,
  );
}

Map<String, Object?> _remoteRepository({
  required String sha256Value,
  required int sizeBytes,
}) {
  return <String, Object?>{
    'id': _repository,
    'sha': _remoteCommit,
    'private': false,
    'gated': false,
    'tags': <String>['gguf', 'conversational'],
    'cardData': <String, Object?>{'license': 'apache-2.0'},
    'siblings': <Object?>[
      <String, Object?>{
        'rfilename': _fileName,
        'size': sizeBytes,
        'lfs': <String, Object?>{'sha256': sha256Value, 'size': sizeBytes},
      },
    ],
  };
}
