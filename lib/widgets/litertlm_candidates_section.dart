import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/litertlm_model_artifact.dart';
import '../presentation/model_identity_presentation.dart';
import '../services/model_download_service.dart';
import '../services/model_manager_service.dart';

typedef LiteRtLmExternalUriLauncher = Future<bool> Function(Uri uri);

/// Displays the small, static catalog of exact LiteRT-LM artifacts that have
/// already been qualified against Local AI Lab's pinned runtime.
class LiteRtLmCandidatesSection extends StatefulWidget {
  const LiteRtLmCandidatesSection({
    super.key,
    required this.installedArtifactIds,
    required this.installedInventoryLoading,
    this.downloadService,
    this.onModelInstalled,
    this.externalUriLauncher,
  });

  final Set<String> installedArtifactIds;
  final bool installedInventoryLoading;
  final ModelDownloadService? downloadService;
  final Future<void> Function()? onModelInstalled;
  final LiteRtLmExternalUriLauncher? externalUriLauncher;

  @override
  State<LiteRtLmCandidatesSection> createState() =>
      _LiteRtLmCandidatesSectionState();
}

class _LiteRtLmCandidatesSectionState extends State<LiteRtLmCandidatesSection> {
  late final ModelDownloadService _downloadService;
  late final LiteRtLmExternalUriLauncher _externalUriLauncher;
  final Map<String, _LiteRtLmDownloadState> _states =
      <String, _LiteRtLmDownloadState>{};
  int _refreshGeneration = 0;

  bool get _hasActiveDownload =>
      _states.values.any((_LiteRtLmDownloadState state) => state.isDownloading);

  @override
  void initState() {
    super.initState();
    _downloadService = widget.downloadService ?? ModelDownloadService();
    _externalUriLauncher = widget.externalUriLauncher ?? _launchExternalUri;
    unawaited(_refreshStates());
  }

  @override
  void didUpdateWidget(covariant LiteRtLmCandidatesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.installedInventoryLoading !=
            widget.installedInventoryLoading ||
        !setEquals(
          oldWidget.installedArtifactIds,
          widget.installedArtifactIds,
        )) {
      unawaited(_refreshStates());
    }
  }

  @override
  void dispose() {
    _refreshGeneration++;
    for (final _LiteRtLmDownloadState state in _states.values) {
      state.cancelToken?.cancel();
    }
    super.dispose();
  }

  Future<bool> _launchExternalUri(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _refreshStates() async {
    final int generation = ++_refreshGeneration;
    if (mounted) {
      setState(() {
        for (final LiteRtLmModelArtifact artifact
            in approvedLiteRtLmArtifacts) {
          _states[artifact.identity] = const _LiteRtLmDownloadState(
            isChecking: true,
          );
        }
      });
    }

    if (widget.installedInventoryLoading) return;

    final Map<String, _LiteRtLmDownloadState> refreshed =
        <String, _LiteRtLmDownloadState>{};
    for (final LiteRtLmModelArtifact artifact in approvedLiteRtLmArtifacts) {
      if (widget.installedArtifactIds.contains(artifact.identity)) {
        refreshed[artifact.identity] = _LiteRtLmDownloadState(
          installed: true,
          totalBytes: artifact.sizeBytes,
        );
        continue;
      }

      final InstalledArtifactSizeStatus sizeStatus = await _downloadService
          .installedArtifactSizeStatus(
            fileName: artifact.filename,
            expectedSizeBytes: artifact.sizeBytes,
          );
      final bool conflictingFile =
          sizeStatus == InstalledArtifactSizeStatus.matchesExpectedSize ||
          sizeStatus == InstalledArtifactSizeStatus.differentSize;
      final bool storageUnavailable =
          sizeStatus == InstalledArtifactSizeStatus.storageUnavailable;
      final int partialBytes = conflictingFile || storageUnavailable
          ? 0
          : await _downloadService.partialBytes(artifact.filename);
      refreshed[artifact.identity] = _LiteRtLmDownloadState(
        fileConflict: conflictingFile,
        storageUnavailable: storageUnavailable,
        partialBytes: partialBytes,
        receivedBytes: partialBytes,
        totalBytes: artifact.sizeBytes,
      );
    }

    if (!mounted || generation != _refreshGeneration) return;
    setState(() {
      _states
        ..clear()
        ..addAll(refreshed);
    });
  }

  Future<void> _openUri(Uri uri) async {
    bool opened = false;
    try {
      opened = await _externalUriLauncher(uri);
    } on Object {
      opened = false;
    }
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open the requested information.'),
      ),
    );
  }

  Future<void> _startDownload(LiteRtLmModelArtifact artifact) async {
    if (_hasActiveDownload) return;
    final _LiteRtLmDownloadState current =
        _states[artifact.identity] ?? const _LiteRtLmDownloadState();
    if (current.partialBytes <= 0) {
      final bool confirmed = await _confirmDownload(artifact);
      if (!confirmed || !mounted || _hasActiveDownload) return;
    }

    final DownloadCancelToken token = DownloadCancelToken();
    DateTime lastTick = DateTime.fromMillisecondsSinceEpoch(0);
    setState(() {
      _states[artifact.identity] = current.copyWith(
        isDownloading: true,
        cancelToken: token,
        clearMessage: true,
        receivedBytes: current.partialBytes,
        totalBytes: artifact.sizeBytes,
      );
    });

    final DownloadResult result = await _downloadService.download(
      url: Uri.parse(artifact.downloadUrl),
      fileName: artifact.filename,
      expectedSha256: artifact.sha256,
      cancelToken: token,
      onProgress: (DownloadProgress progress) {
        final DateTime now = DateTime.now();
        if (now.difference(lastTick) < const Duration(milliseconds: 250)) {
          return;
        }
        lastTick = now;
        if (!mounted) return;
        final _LiteRtLmDownloadState state =
            _states[artifact.identity] ?? current;
        setState(() {
          _states[artifact.identity] = state.copyWith(
            receivedBytes: progress.receivedBytes,
            totalBytes: progress.totalBytes ?? artifact.sizeBytes,
          );
        });
      },
    );

    if (!mounted) return;
    if (result.isSuccess) {
      setState(() {
        _states[artifact.identity] = _LiteRtLmDownloadState(
          installed: true,
          totalBytes: artifact.sizeBytes,
          message: 'Installed and available in Run and Compare.',
        );
      });
      await widget.onModelInstalled?.call();
      return;
    }

    final bool conflictingFile = result.outcome == DownloadOutcome.fileConflict;
    final int partialBytes =
        result.outcome == DownloadOutcome.checksumFailed ||
            result.outcome == DownloadOutcome.storageError
        ? 0
        : await _downloadService.partialBytes(artifact.filename);
    if (!mounted) return;
    setState(() {
      _states[artifact.identity] = _LiteRtLmDownloadState(
        fileConflict: conflictingFile,
        partialBytes: partialBytes,
        receivedBytes: partialBytes,
        totalBytes: artifact.sizeBytes,
        message: _messageFor(result),
      );
    });
  }

  Future<bool> _confirmDownload(LiteRtLmModelArtifact artifact) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final ThemeData theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Download LiteRT-LM Candidate?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This exact artifact has been audited and qualified with '
                  'Local AI Lab’s pinned LiteRT-LM runtime. Performance and '
                  'memory behavior can still vary by phone.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(artifact.filename, style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                Text(
                  '${_formatBytes(artifact.sizeBytes)} · ${artifact.license}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('litertlm-dialog-license'),
                  onPressed: () => _openUri(Uri.parse(artifact.licenseUrl)),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('View license information'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirm-litertlm-download'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Download Candidate'),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _discardPartial(LiteRtLmModelArtifact artifact) async {
    if (_hasActiveDownload) return;
    await _downloadService.discardPartial(artifact.filename);
    if (!mounted) return;
    setState(() {
      _states[artifact.identity] = _LiteRtLmDownloadState(
        totalBytes: artifact.sizeBytes,
      );
    });
  }

  String _messageFor(DownloadResult result) {
    switch (result.outcome) {
      case DownloadOutcome.completed:
        return 'Installed and available in Run and Compare.';
      case DownloadOutcome.cancelled:
        return 'Stopped. Partial file kept — Resume continues the download.';
      case DownloadOutcome.networkError:
        return 'Download failed: ${result.message ?? 'network error'}. '
            'Partial file kept.';
      case DownloadOutcome.checksumFailed:
        return 'Checksum did not match. The candidate file was discarded.';
      case DownloadOutcome.storageError:
        return 'Storage error: '
            '${result.message ?? 'could not write the file'}.';
      case DownloadOutcome.fileConflict:
        return 'A different file already uses this model filename.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      key: const Key('litertlm-candidates-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.offline_bolt_outlined,
              color: theme.colorScheme.primary,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Curated LiteRT-LM',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Exact, immutable artifacts already qualified with the app’s pinned '
          'LiteRT-LM runtime. The catalog is built into the app and opening it '
          'uses no network connection.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        for (final LiteRtLmModelArtifact artifact
            in approvedLiteRtLmArtifacts) ...[
          _buildArtifactCard(context, artifact),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 12),
        Divider(color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              Icons.travel_explore_rounded,
              color: theme.colorScheme.primary,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              'GGUF Discovery',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildArtifactCard(
    BuildContext context,
    LiteRtLmModelArtifact artifact,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final _LiteRtLmDownloadState state =
        _states[artifact.identity] ??
        const _LiteRtLmDownloadState(isChecking: true);
    final String conciseName = conciseModelName(
      artifact.displayName,
      ModelEngine.litertlm,
    );

    return Card(
      key: ValueKey<String>('litertlm-candidate-${artifact.filename}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    conciseName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const ModelRuntimeBadge(engine: ModelEngine.litertlm),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Curated · runtime qualified',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.tertiary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(artifact.filename, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              '${_formatBytes(artifact.sizeBytes)} · ${artifact.license}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _contextLabel(artifact),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              artifact.repository,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => _openUri(Uri.parse(artifact.sourceUrl)),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('View source'),
                ),
                TextButton.icon(
                  onPressed: () => _openUri(Uri.parse(artifact.licenseUrl)),
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('View license'),
                ),
              ],
            ),
            _buildDownloadArea(artifact, state),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadArea(
    LiteRtLmModelArtifact artifact,
    _LiteRtLmDownloadState state,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    if (state.isChecking) {
      return const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Expanded(child: Text('Checking local model files…')),
        ],
      );
    }

    if (state.installed) {
      return Row(
        key: ValueKey<String>('litertlm-installed-${artifact.filename}'),
        children: [
          Icon(Icons.check_circle_outline, color: colors.primary, size: 20),
          const SizedBox(width: 8),
          Text(
            'Installed',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    if (state.fileConflict) {
      return Text(
        'A different or unrecognized file already uses this exact filename. '
        'It was not changed.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: colors.error,
          height: 1.35,
        ),
      );
    }

    if (state.storageUnavailable) {
      return Text(
        'The app cannot inspect its model storage right now.',
        style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
      );
    }

    if (state.isDownloading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: state.fraction),
          const SizedBox(height: 6),
          Text(state.progressLabel, style: theme.textTheme.bodySmall),
          TextButton.icon(
            onPressed: () => state.cancelToken?.cancel(),
            icon: const Icon(Icons.stop_rounded, size: 18),
            label: const Text('Stop'),
          ),
        ],
      );
    }

    final bool hasPartial = state.partialBytes > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasPartial) ...[
          Text(
            'Partial download: ${_formatBytes(state.partialBytes)} of '
            '${_formatBytes(artifact.sizeBytes)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        if (state.message != null) ...[
          Text(state.message!, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonalIcon(
              key: ValueKey<String>(
                '${hasPartial ? 'litertlm-resume' : 'litertlm-download'}-'
                '${artifact.filename}',
              ),
              onPressed: _hasActiveDownload
                  ? null
                  : () => _startDownload(artifact),
              icon: Icon(
                hasPartial ? Icons.play_arrow_rounded : Icons.download_rounded,
                size: 18,
              ),
              label: Text(hasPartial ? 'Resume' : 'Download'),
            ),
            if (hasPartial)
              TextButton(
                onPressed: _hasActiveDownload
                    ? null
                    : () => _discardPartial(artifact),
                child: const Text('Discard'),
              ),
          ],
        ),
      ],
    );
  }

  String _contextLabel(LiteRtLmModelArtifact artifact) {
    final String artifactContext = _formatTokenCount(
      artifact.artifactContextTokens,
    );
    final String runtimeContext = _formatTokenCount(artifact.contextTokens);
    if (artifact.artifactContextTokens == artifact.contextTokens) {
      return 'Context: $runtimeContext tokens';
    }
    return 'Artifact context: $artifactContext tokens · '
        'app runtime: $runtimeContext tokens';
  }

  static String _formatTokenCount(int value) {
    final String digits = value.toString();
    if (digits.length <= 3) return digits;
    final int firstGroup = digits.length % 3;
    final List<String> groups = <String>[];
    int index = 0;
    if (firstGroup > 0) {
      groups.add(digits.substring(0, firstGroup));
      index = firstGroup;
    }
    while (index < digits.length) {
      groups.add(digits.substring(index, index + 3));
      index += 3;
    }
    return groups.join(',');
  }

  static String _formatBytes(int bytes) {
    const int gb = 1000 * 1000 * 1000;
    const int mb = 1000 * 1000;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    return '${(bytes / mb).toStringAsFixed(0)} MB';
  }
}

class _LiteRtLmDownloadState {
  const _LiteRtLmDownloadState({
    this.isChecking = false,
    this.isDownloading = false,
    this.installed = false,
    this.fileConflict = false,
    this.storageUnavailable = false,
    this.partialBytes = 0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.message,
    this.cancelToken,
  });

  final bool isChecking;
  final bool isDownloading;
  final bool installed;
  final bool fileConflict;
  final bool storageUnavailable;
  final int partialBytes;
  final int receivedBytes;
  final int totalBytes;
  final String? message;
  final DownloadCancelToken? cancelToken;

  double? get fraction {
    if (totalBytes <= 0) return null;
    final double value = receivedBytes / totalBytes;
    return value > 1 ? 1 : value;
  }

  String get progressLabel {
    if (totalBytes <= 0) return _formatProgressBytes(receivedBytes);
    return '${_formatProgressBytes(receivedBytes)} of '
        '${_formatProgressBytes(totalBytes)}';
  }

  _LiteRtLmDownloadState copyWith({
    bool? isChecking,
    bool? isDownloading,
    bool? installed,
    bool? fileConflict,
    bool? storageUnavailable,
    int? partialBytes,
    int? receivedBytes,
    int? totalBytes,
    String? message,
    bool clearMessage = false,
    DownloadCancelToken? cancelToken,
  }) {
    return _LiteRtLmDownloadState(
      isChecking: isChecking ?? this.isChecking,
      isDownloading: isDownloading ?? this.isDownloading,
      installed: installed ?? this.installed,
      fileConflict: fileConflict ?? this.fileConflict,
      storageUnavailable: storageUnavailable ?? this.storageUnavailable,
      partialBytes: partialBytes ?? this.partialBytes,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      message: clearMessage ? null : message ?? this.message,
      cancelToken: cancelToken ?? this.cancelToken,
    );
  }

  static String _formatProgressBytes(int bytes) {
    const int mb = 1000 * 1000;
    if (bytes < mb) return '${(bytes / 1000).toStringAsFixed(0)} KB';
    return '${(bytes / mb).toStringAsFixed(1)} MB';
  }
}
