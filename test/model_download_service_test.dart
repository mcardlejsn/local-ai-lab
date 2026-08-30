import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/services/model_download_service.dart';
import 'package:path/path.dart' as p;

void main() {
  group('installed artifact size precheck', () {
    late Directory temporaryDirectory;
    late ModelDownloadService service;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'local_ai_lab_size_test_',
      );
      service = ModelDownloadService(
        modelsDirectoryResolver: () async => temporaryDirectory,
      );
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('reports an absent file without hashing', () async {
      final status = await service.installedArtifactSizeStatus(
        fileName: 'candidate.gguf',
        expectedSizeBytes: 5,
      );

      expect(status, InstalledArtifactSizeStatus.absent);
    });

    test('accepts the expected byte size without hashing', () async {
      await File(
        p.join(temporaryDirectory.path, 'candidate.gguf'),
      ).writeAsBytes(<int>[1, 2, 3, 4, 5]);

      final status = await service.installedArtifactSizeStatus(
        fileName: 'candidate.gguf',
        expectedSizeBytes: 5,
      );

      expect(status, InstalledArtifactSizeStatus.matchesExpectedSize);
    });

    test('reports a different byte size without hashing', () async {
      await File(
        p.join(temporaryDirectory.path, 'candidate.gguf'),
      ).writeAsBytes(<int>[1, 2, 3]);

      final status = await service.installedArtifactSizeStatus(
        fileName: 'candidate.gguf',
        expectedSizeBytes: 5,
      );

      expect(status, InstalledArtifactSizeStatus.differentSize);
    });

    test('reports unavailable storage', () async {
      final ModelDownloadService unavailable = ModelDownloadService(
        modelsDirectoryResolver: () async => null,
      );

      final status = await unavailable.installedArtifactSizeStatus(
        fileName: 'candidate.gguf',
        expectedSizeBytes: 5,
      );

      expect(status, InstalledArtifactSizeStatus.storageUnavailable);
    });
  });

  group('exact installed artifact protection', () {
    late Directory temporaryDirectory;
    late ModelDownloadService service;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'local_ai_lab_download_test_',
      );
      service = ModelDownloadService(
        modelsDirectoryResolver: () async => temporaryDirectory,
      );
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('reports an absent exact artifact', () async {
      final status = await service.installedArtifactStatus(
        fileName: 'candidate.gguf',
        expectedSha256: _sha256(<int>[1, 2, 3]),
      );

      expect(status, InstalledArtifactStatus.absent);
    });

    test(
      'accepts a matching existing artifact without opening the network',
      () async {
        final List<int> bytes = <int>[1, 2, 3, 4, 5];
        final File target = File(
          p.join(temporaryDirectory.path, 'candidate.gguf'),
        );
        await target.writeAsBytes(bytes);
        final String expectedSha256 = _sha256(bytes);

        final status = await service.installedArtifactStatus(
          fileName: 'candidate.gguf',
          expectedSha256: expectedSha256,
        );
        final DownloadResult result = await service.download(
          url: Uri.parse('http://127.0.0.1:1/should-not-be-requested'),
          fileName: 'candidate.gguf',
          expectedSha256: expectedSha256,
        );

        expect(status, InstalledArtifactStatus.matchesExpected);
        expect(result.outcome, DownloadOutcome.completed);
        expect(result.message, 'Already installed.');
        expect(await target.readAsBytes(), bytes);
      },
    );

    test('refuses a different same-named file without changing it', () async {
      final List<int> installedBytes = <int>[9, 8, 7, 6];
      final File target = File(
        p.join(temporaryDirectory.path, 'candidate.gguf'),
      );
      await target.writeAsBytes(installedBytes);
      final String expectedSha256 = _sha256(<int>[1, 2, 3, 4]);

      final status = await service.installedArtifactStatus(
        fileName: 'candidate.gguf',
        expectedSha256: expectedSha256,
      );
      final DownloadResult result = await service.download(
        url: Uri.parse('http://127.0.0.1:1/should-not-be-requested'),
        fileName: 'candidate.gguf',
        expectedSha256: expectedSha256,
      );

      expect(status, InstalledArtifactStatus.differentFile);
      expect(result.outcome, DownloadOutcome.fileConflict);
      expect(await target.readAsBytes(), installedBytes);
      expect(await File('${target.path}.part').exists(), isFalse);
    });

    test('reports unavailable storage without requesting a download', () async {
      final ModelDownloadService unavailable = ModelDownloadService(
        modelsDirectoryResolver: () async => null,
      );

      final status = await unavailable.installedArtifactStatus(
        fileName: 'candidate.gguf',
        expectedSha256: _sha256(<int>[1, 2, 3]),
      );
      final DownloadResult result = await unavailable.download(
        url: Uri.parse('http://127.0.0.1:1/should-not-be-requested'),
        fileName: 'candidate.gguf',
        expectedSha256: _sha256(<int>[1, 2, 3]),
      );

      expect(status, InstalledArtifactStatus.storageUnavailable);
      expect(result.outcome, DownloadOutcome.storageError);
    });
  });
}

String _sha256(List<int> bytes) => sha256.convert(bytes).toString();
