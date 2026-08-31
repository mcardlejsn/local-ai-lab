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
    late int hashCount;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'local_ai_lab_download_test_',
      );
      hashCount = 0;
      service = ModelDownloadService(
        modelsDirectoryResolver: () async => temporaryDirectory,
        fileSha256Resolver: (File file) async {
          hashCount++;
          return sha256
              .bind(file.openRead())
              .first
              .then((Digest digest) => digest.toString());
        },
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
      expect(hashCount, 0);
    });

    test('reuses the saved digest for an unchanged installed file', () async {
      final List<int> bytes = <int>[1, 2, 3, 4, 5];
      await File(
        p.join(temporaryDirectory.path, 'candidate.gguf'),
      ).writeAsBytes(bytes);
      final String expectedSha256 = _sha256(bytes);

      final first = await service.installedArtifactStatus(
        fileName: 'candidate.gguf',
        expectedSha256: expectedSha256,
      );
      final second = await service.installedArtifactStatus(
        fileName: 'candidate.gguf',
        expectedSha256: expectedSha256,
      );

      expect(first, InstalledArtifactStatus.matchesExpected);
      expect(second, InstalledArtifactStatus.matchesExpected);
      expect(hashCount, 1);
    });

    test('rehashes when the installed file size changes', () async {
      final File target = File(
        p.join(temporaryDirectory.path, 'candidate.gguf'),
      );
      final List<int> originalBytes = <int>[1, 2, 3, 4];
      await target.writeAsBytes(originalBytes);
      final String expectedSha256 = _sha256(originalBytes);
      await service.installedArtifactStatus(
        fileName: 'candidate.gguf',
        expectedSha256: expectedSha256,
      );

      await target.writeAsBytes(<int>[1, 2, 3, 4, 5]);
      final status = await service.installedArtifactStatus(
        fileName: 'candidate.gguf',
        expectedSha256: expectedSha256,
      );

      expect(status, InstalledArtifactStatus.differentFile);
      expect(hashCount, 2);
    });

    test(
      'rehashes when the installed file modification time changes',
      () async {
        final File target = File(
          p.join(temporaryDirectory.path, 'candidate.gguf'),
        );
        final List<int> bytes = <int>[1, 2, 3, 4];
        await target.writeAsBytes(bytes);
        final DateTime firstModified = DateTime.utc(2026, 8, 30, 20);
        await target.setLastModified(firstModified);
        final String expectedSha256 = _sha256(bytes);
        await service.installedArtifactStatus(
          fileName: 'candidate.gguf',
          expectedSha256: expectedSha256,
        );

        await target.setLastModified(
          firstModified.add(const Duration(seconds: 1)),
        );
        final status = await service.installedArtifactStatus(
          fileName: 'candidate.gguf',
          expectedSha256: expectedSha256,
        );

        expect(status, InstalledArtifactStatus.matchesExpected);
        expect(hashCount, 2);
      },
    );

    test('rehashes when the saved verification record is missing', () async {
      final File target = File(
        p.join(temporaryDirectory.path, 'candidate.gguf'),
      );
      final List<int> bytes = <int>[1, 2, 3, 4];
      await target.writeAsBytes(bytes);
      final String expectedSha256 = _sha256(bytes);
      await service.installedArtifactStatus(
        fileName: 'candidate.gguf',
        expectedSha256: expectedSha256,
      );
      await File('${target.path}.local_ai_lab_verification.json').delete();

      final status = await service.installedArtifactStatus(
        fileName: 'candidate.gguf',
        expectedSha256: expectedSha256,
      );

      expect(status, InstalledArtifactStatus.matchesExpected);
      expect(hashCount, 2);
    });

    test('rehashes when the saved verification record is invalid', () async {
      final File target = File(
        p.join(temporaryDirectory.path, 'candidate.gguf'),
      );
      final List<int> bytes = <int>[1, 2, 3, 4];
      await target.writeAsBytes(bytes);
      final String expectedSha256 = _sha256(bytes);
      await service.installedArtifactStatus(
        fileName: 'candidate.gguf',
        expectedSha256: expectedSha256,
      );
      await File(
        '${target.path}.local_ai_lab_verification.json',
      ).writeAsString('not json');

      final status = await service.installedArtifactStatus(
        fileName: 'candidate.gguf',
        expectedSha256: expectedSha256,
      );

      expect(status, InstalledArtifactStatus.matchesExpected);
      expect(hashCount, 2);
    });

    test('changed bytes cannot reuse a stale verified digest', () async {
      final File target = File(
        p.join(temporaryDirectory.path, 'candidate.gguf'),
      );
      final List<int> expectedBytes = <int>[1, 2, 3, 4];
      final DateTime firstModified = DateTime.utc(2026, 8, 30, 20);
      await target.writeAsBytes(expectedBytes);
      await target.setLastModified(firstModified);
      final String expectedSha256 = _sha256(expectedBytes);
      await service.installedArtifactStatus(
        fileName: 'candidate.gguf',
        expectedSha256: expectedSha256,
      );

      await target.writeAsBytes(<int>[9, 8, 7, 6]);
      await target.setLastModified(
        firstModified.add(const Duration(seconds: 1)),
      );
      final status = await service.installedArtifactStatus(
        fileName: 'candidate.gguf',
        expectedSha256: expectedSha256,
      );

      expect(status, InstalledArtifactStatus.differentFile);
      expect(hashCount, 2);
    });

    test('reuses the digest calculated by a successful download', () async {
      final List<int> bytes = <int>[1, 2, 3, 4, 5];
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final Future<void> response = server.first.then((request) async {
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      });
      addTearDown(() async => server.close(force: true));

      final DownloadResult result = await service.download(
        url: Uri.parse('http://${server.address.host}:${server.port}/model'),
        fileName: 'candidate.gguf',
        expectedSha256: _sha256(bytes),
      );
      await response;
      final status = await service.installedArtifactStatus(
        fileName: 'candidate.gguf',
        expectedSha256: _sha256(bytes),
      );

      expect(result.outcome, DownloadOutcome.completed);
      expect(status, InstalledArtifactStatus.matchesExpected);
      expect(hashCount, 1);
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
