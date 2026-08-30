import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef ModelsDirectoryResolver = Future<Directory?> Function();

/// Downloads a single model file into the same directory
/// [ModelManagerService.scanModels] reads from.
///
/// The in-flight file is written as `<name>.part`, an extension the scanner
/// deliberately does not recognize, so a partial or corrupt download can never
/// be presented as an installed model. The file is renamed to its real
/// extension only after its sha256 matches the expected digest.
///
/// This service performs no catalog parsing and holds no UI state. It opens a
/// socket only when [download] is called.

/// How a download finished.
enum DownloadOutcome {
  /// The file passed its checksum and is installed under its real name.
  completed,

  /// The caller cancelled. The `.part` file is kept for a later resume.
  cancelled,

  /// The transfer failed or the server refused. The `.part` file is kept.
  networkError,

  /// The bytes arrived but the digest did not match. The `.part` file is
  /// deleted, because resuming a known-bad file would only fail again.
  checksumFailed,

  /// The models directory or the file could not be written.
  storageError,

  /// A different file already occupies the exact destination filename.
  /// Nothing is overwritten or deleted.
  fileConflict,
}

/// Relationship between an installed filename and an expected exact artifact.
enum InstalledArtifactStatus {
  absent,
  matchesExpected,
  differentFile,
  storageUnavailable,
}

/// Cheap relationship between an installed filename and an expected byte
/// size. Unlike [InstalledArtifactStatus], this does not read the file body.
enum InstalledArtifactSizeStatus {
  absent,
  matchesExpectedSize,
  differentSize,
  storageUnavailable,
}

class DownloadResult {
  const DownloadResult(this.outcome, {this.filePath, this.message});

  final DownloadOutcome outcome;

  /// Path to the installed model. Set only when [outcome] is
  /// [DownloadOutcome.completed].
  final String? filePath;

  /// Human-readable detail for the failure cases.
  final String? message;

  bool get isSuccess => outcome == DownloadOutcome.completed;
}

class DownloadProgress {
  const DownloadProgress({required this.receivedBytes, this.totalBytes});

  /// Bytes on disk, including any resumed from a previous attempt.
  final int receivedBytes;

  /// Total size of the finished file, or null when the server did not say.
  final int? totalBytes;

  /// 0.0–1.0, or null when the total is unknown.
  double? get fraction {
    final int? total = totalBytes;
    if (total == null || total <= 0) return null;
    final double value = receivedBytes / total;
    return value > 1.0 ? 1.0 : value;
  }
}

/// Cooperative cancellation. Checked between chunks, so cancelling closes the
/// socket at the next chunk boundary rather than immediately.
class DownloadCancelToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() => _isCancelled = true;
}

class ModelDownloadService {
  ModelDownloadService({this.modelsDirectoryResolver});

  static const String _userAgent = 'LocalAILab/1.0 (Android; Dart:io)';
  static const Duration _connectionTimeout = Duration(seconds: 30);

  final ModelsDirectoryResolver? modelsDirectoryResolver;

  /// The app's external files directory — `Android/data/<package>/files/`,
  /// the directory [ModelManagerService.scanModels] reads. Downloads land
  /// here rather than in a `models/` subfolder, so an installed model is one
  /// level in from the app's data folder instead of two.
  Future<Directory?> resolveModelsDirectory() async {
    final ModelsDirectoryResolver? override = modelsDirectoryResolver;
    if (override != null) return override();

    final Directory? extDir = await getExternalStorageDirectory();
    if (extDir == null) return null;
    if (!await extDir.exists()) {
      await extDir.create(recursive: true);
    }
    return extDir;
  }

  /// Checks whether [fileName] is the exact artifact identified by
  /// [expectedSha256]. A same-named file with different bytes is never treated
  /// as installed for that artifact.
  Future<InstalledArtifactStatus> installedArtifactStatus({
    required String fileName,
    required String expectedSha256,
  }) async {
    try {
      final Directory? modelsDir = await resolveModelsDirectory();
      if (modelsDir == null) {
        return InstalledArtifactStatus.storageUnavailable;
      }
      return await _installedArtifactStatus(
        File(p.join(modelsDir.path, fileName)),
        expectedSha256,
      );
    } on FileSystemException {
      return InstalledArtifactStatus.storageUnavailable;
    }
  }

  /// Checks only whether [fileName] exists and has [expectedSizeBytes].
  ///
  /// This is suitable for an immediate UI prefilter when saved provenance is
  /// available. It is not proof of artifact identity; callers must retain
  /// [installedArtifactStatus] for exact sha256 verification.
  Future<InstalledArtifactSizeStatus> installedArtifactSizeStatus({
    required String fileName,
    required int expectedSizeBytes,
  }) async {
    try {
      final Directory? modelsDir = await resolveModelsDirectory();
      if (modelsDir == null) {
        return InstalledArtifactSizeStatus.storageUnavailable;
      }
      final File target = File(p.join(modelsDir.path, fileName));
      if (!await target.exists()) return InstalledArtifactSizeStatus.absent;
      return await target.length() == expectedSizeBytes
          ? InstalledArtifactSizeStatus.matchesExpectedSize
          : InstalledArtifactSizeStatus.differentSize;
    } on FileSystemException {
      return InstalledArtifactSizeStatus.storageUnavailable;
    }
  }

  /// Bytes already downloaded for [fileName], or 0 if there is no partial file.
  Future<int> partialBytes(String fileName) async {
    final Directory? modelsDir = await resolveModelsDirectory();
    if (modelsDir == null) return 0;
    final File part = File(p.join(modelsDir.path, '$fileName.part'));
    if (!await part.exists()) return 0;
    return part.length();
  }

  /// Whether [fileName] is already installed under its real extension.
  Future<bool> isInstalled(String fileName) async {
    final Directory? modelsDir = await resolveModelsDirectory();
    if (modelsDir == null) return false;
    return File(p.join(modelsDir.path, fileName)).exists();
  }

  /// Removes a partial download at the user's request.
  Future<void> discardPartial(String fileName) async {
    final Directory? modelsDir = await resolveModelsDirectory();
    if (modelsDir == null) return;
    final File part = File(p.join(modelsDir.path, '$fileName.part'));
    if (await part.exists()) {
      await part.delete();
    }
  }

  /// Downloads [url] to [fileName] in the app's external files directory,
  /// resuming an existing `.part` when one is present.
  ///
  /// [expectedSha256] is the digest of the complete file, compared
  /// case-insensitively. [fileName] must carry the model's real extension
  /// (e.g. `Qwen2.5-1.5B-Instruct-Q4_K_M.gguf`).
  Future<DownloadResult> download({
    required Uri url,
    required String fileName,
    required String expectedSha256,
    void Function(DownloadProgress progress)? onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    final Directory? modelsDir = await resolveModelsDirectory();
    if (modelsDir == null) {
      return const DownloadResult(
        DownloadOutcome.storageError,
        message: 'No external storage directory available.',
      );
    }

    final File target = File(p.join(modelsDir.path, fileName));
    final InstalledArtifactStatus installedStatus;
    try {
      installedStatus = await _installedArtifactStatus(target, expectedSha256);
    } on FileSystemException catch (error) {
      return DownloadResult(
        DownloadOutcome.storageError,
        message: error.message,
      );
    }
    switch (installedStatus) {
      case InstalledArtifactStatus.matchesExpected:
        return DownloadResult(
          DownloadOutcome.completed,
          filePath: target.path,
          message: 'Already installed.',
        );
      case InstalledArtifactStatus.differentFile:
        return const DownloadResult(
          DownloadOutcome.fileConflict,
          message: 'A different file already uses this filename.',
        );
      case InstalledArtifactStatus.storageUnavailable:
        return const DownloadResult(
          DownloadOutcome.storageError,
          message: 'The installed file could not be inspected.',
        );
      case InstalledArtifactStatus.absent:
        break;
    }

    final File part = File(p.join(modelsDir.path, '$fileName.part'));

    if (cancelToken?.isCancelled ?? false) {
      return const DownloadResult(DownloadOutcome.cancelled);
    }

    final HttpClient client = HttpClient()
      ..connectionTimeout = _connectionTimeout;

    IOSink? sink;
    try {
      int resumeFrom = await part.exists() ? await part.length() : 0;

      HttpClientRequest request = await client.getUrl(url);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      if (resumeFrom > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$resumeFrom-');
      }
      HttpClientResponse response = await request.close();

      bool append = false;
      int? totalBytes;

      if (resumeFrom > 0 && response.statusCode == HttpStatus.partialContent) {
        final _ContentRange? range = _parseContentRange(
          response.headers.value(HttpHeaders.contentRangeHeader),
        );
        if (range == null || range.start != resumeFrom) {
          // The server honoured a range, but not the one asked for. Appending
          // these bytes would produce a file that only fails at the checksum.
          await response.drain<void>();
          debugPrint('Range mismatch for $fileName; restarting from zero.');
          await part.delete();
          resumeFrom = 0;

          request = await client.getUrl(url);
          request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
          response = await request.close();
          if (response.statusCode != HttpStatus.ok) {
            await response.drain<void>();
            return DownloadResult(
              DownloadOutcome.networkError,
              message: 'Server returned HTTP ${response.statusCode}.',
            );
          }
          totalBytes = _contentLengthOrNull(response);
        } else {
          append = true;
          totalBytes = range.total;
        }
      } else if (resumeFrom > 0 && response.statusCode == HttpStatus.ok) {
        // Range ignored: the body is the whole file, so the partial bytes are
        // now meaningless. Overwrite from the start; never append.
        await part.delete();
        resumeFrom = 0;
        totalBytes = _contentLengthOrNull(response);
      } else if (resumeFrom > 0 &&
          response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
        // The partial file is at or past the end of the remote file — it does
        // not match this URL. Start over.
        await response.drain<void>();
        await part.delete();
        resumeFrom = 0;

        request = await client.getUrl(url);
        request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
        response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          await response.drain<void>();
          return DownloadResult(
            DownloadOutcome.networkError,
            message: 'Server returned HTTP ${response.statusCode}.',
          );
        }
        totalBytes = _contentLengthOrNull(response);
      } else if (response.statusCode == HttpStatus.ok) {
        totalBytes = _contentLengthOrNull(response);
      } else {
        await response.drain<void>();
        return DownloadResult(
          DownloadOutcome.networkError,
          message: 'Server returned HTTP ${response.statusCode}.',
        );
      }

      int received = resumeFrom;
      onProgress?.call(
        DownloadProgress(receivedBytes: received, totalBytes: totalBytes),
      );

      sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);

      bool cancelled = false;
      await for (final List<int> chunk in response) {
        if (cancelToken?.isCancelled ?? false) {
          cancelled = true;
          break;
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(
          DownloadProgress(receivedBytes: received, totalBytes: totalBytes),
        );
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (cancelled) {
        // The `.part` file stays on disk so the next attempt can resume.
        return const DownloadResult(DownloadOutcome.cancelled);
      }

      final String actual = await _sha256OfFile(part);
      if (actual.toLowerCase() != expectedSha256.toLowerCase()) {
        await part.delete();
        return DownloadResult(
          DownloadOutcome.checksumFailed,
          message: 'Expected $expectedSha256, got $actual.',
        );
      }

      await part.rename(target.path);
      return DownloadResult(DownloadOutcome.completed, filePath: target.path);
    } on SocketException catch (e) {
      return DownloadResult(DownloadOutcome.networkError, message: e.message);
    } on HttpException catch (e) {
      return DownloadResult(DownloadOutcome.networkError, message: e.message);
    } on FileSystemException catch (e) {
      return DownloadResult(DownloadOutcome.storageError, message: e.message);
    } catch (e) {
      return DownloadResult(
        DownloadOutcome.networkError,
        message: e.toString(),
      );
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {
          // The partial file is kept regardless; a close failure here says
          // nothing useful beyond what the caught error already reported.
        }
      }
      client.close(force: true);
    }
  }

  /// Streams the file through sha256 rather than loading ~1GB into memory.
  Future<String> _sha256OfFile(File file) async {
    final Digest digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<InstalledArtifactStatus> _installedArtifactStatus(
    File target,
    String expectedSha256,
  ) async {
    if (!await target.exists()) return InstalledArtifactStatus.absent;
    final String actualSha256 = await _sha256OfFile(target);
    return actualSha256.toLowerCase() == expectedSha256.toLowerCase()
        ? InstalledArtifactStatus.matchesExpected
        : InstalledArtifactStatus.differentFile;
  }

  int? _contentLengthOrNull(HttpClientResponse response) {
    final int length = response.contentLength;
    return length < 0 ? null : length;
  }

  /// Parses `bytes <start>-<end>/<total>`. Returns null for anything else,
  /// including `*/<total>` and an unknown total.
  _ContentRange? _parseContentRange(String? header) {
    if (header == null) return null;
    final RegExpMatch? match = RegExp(
      r'^bytes\s+(\d+)-(\d+)/(\d+)$',
    ).firstMatch(header.trim());
    if (match == null) return null;
    final int? start = int.tryParse(match.group(1)!);
    final int? total = int.tryParse(match.group(3)!);
    if (start == null || total == null) return null;
    return _ContentRange(start: start, total: total);
  }
}

class _ContentRange {
  const _ContentRange({required this.start, required this.total});

  final int start;
  final int total;
}
