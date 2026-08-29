import 'package:flutter/material.dart';

import '../models/gguf_candidate_assessment.dart';
import '../models/model_catalog.dart';
import '../services/model_download_service.dart';
import '../services/model_manager_service.dart';
import 'benchmark_screen.dart';
import 'gguf_discovery_screen.dart';
import 'settings_screen.dart';

/// Lists the bundled verified catalog and links to temporary GGUF discovery.
///
/// No network call happens when this screen opens — [kModelCatalog] is compiled
/// into the APK and installed-state checks are local. Network activity requires
/// an explicit Discover action on the discovery screen or Download below.
class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({super.key, required this.modelManager});

  /// Rescanned after a successful install so the new model appears in the
  /// picker without a manual refresh.
  final ModelManagerService modelManager;

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  static const Color _bgColor = Color(0xFF121212);
  static const Color _surfaceColor = Color(0xFF1E1E1E);
  static const Color _accentBlue = Color(0xFF90CAF9);
  static const Color _successGreen = Color(0xFF81C784);

  final ModelDownloadService _downloader = ModelDownloadService();
  final Map<String, _EntryState> _states = <String, _EntryState>{};

  @override
  void initState() {
    super.initState();
    for (final CatalogModel model in kModelCatalog) {
      _states[model.id] = const _EntryState();
    }
    _refreshAll();
  }

  @override
  void dispose() {
    // Leaving the screen stops any transfer. The `.part` file stays on disk,
    // so the next visit resumes rather than restarts.
    for (final _EntryState state in _states.values) {
      state.cancelToken?.cancel();
    }
    super.dispose();
  }

  Future<void> _refreshAll() async {
    for (final CatalogModel model in kModelCatalog) {
      final bool installed = await _downloader.isInstalled(model.fileName);
      final int partial = installed
          ? 0
          : await _downloader.partialBytes(model.fileName);
      if (!mounted) return;
      setState(() {
        _states[model.id] = _states[model.id]!.copyWith(
          installed: installed,
          partialBytes: partial,
        );
      });
    }
  }

  Future<void> _startDownload(CatalogModel model) async {
    final DownloadCancelToken token = DownloadCancelToken();
    DateTime lastTick = DateTime.fromMillisecondsSinceEpoch(0);

    setState(() {
      _states[model.id] = _states[model.id]!.copyWith(
        isDownloading: true,
        cancelToken: token,
        message: null,
        receivedBytes: _states[model.id]!.partialBytes,
        totalBytes: model.sizeBytes,
      );
    });

    final DownloadResult result = await _downloader.download(
      url: model.uri,
      fileName: model.fileName,
      expectedSha256: model.sha256,
      cancelToken: token,
      onProgress: (DownloadProgress progress) {
        // The callback fires per chunk; repainting that often would cost more
        // than the download.
        final DateTime now = DateTime.now();
        if (now.difference(lastTick) < const Duration(milliseconds: 250)) {
          return;
        }
        lastTick = now;
        if (!mounted) return;
        setState(() {
          _states[model.id] = _states[model.id]!.copyWith(
            receivedBytes: progress.receivedBytes,
            totalBytes: progress.totalBytes ?? model.sizeBytes,
          );
        });
      },
    );

    if (!mounted) return;

    setState(() {
      _states[model.id] = _states[model.id]!.copyWith(
        isDownloading: false,
        clearCancelToken: true,
        message: _messageFor(result),
      );
    });

    await _refreshAll();

    if (result.isSuccess) {
      await widget.modelManager.scanModels();
    }

    if (!mounted) return;
    final String? note = _messageFor(result);
    if (note != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
    }
  }

  String? _messageFor(DownloadResult result) {
    switch (result.outcome) {
      case DownloadOutcome.completed:
        return 'Installed. It will appear in the model picker.';
      case DownloadOutcome.cancelled:
        return 'Stopped. Partial file kept — Resume picks up where it left off.';
      case DownloadOutcome.networkError:
        return 'Download failed: ${result.message ?? 'network error'}. '
            'Partial file kept.';
      case DownloadOutcome.checksumFailed:
        return 'Checksum did not match. The file was discarded, not installed.';
      case DownloadOutcome.storageError:
        return 'Storage error: ${result.message ?? 'could not write the file'}.';
      case DownloadOutcome.fileConflict:
        return 'A different file already uses this model filename. '
            'It was not changed.';
    }
  }

  Future<void> _discard(CatalogModel model) async {
    await _downloader.discardPartial(model.fileName);
    if (!mounted) return;
    setState(() {
      _states[model.id] = _states[model.id]!.copyWith(message: null);
    });
    await _refreshAll();
  }

  Future<void> _openCandidateBenchmark(GgufCandidateArtifact artifact) async {
    await widget.modelManager.scanModels();
    if (!mounted) return;

    final List<ModelInfo> matches = widget.modelManager.availableModels
        .where(
          (ModelInfo model) =>
              model.engine == ModelEngine.gguf &&
              model.name == artifact.fileName,
        )
        .toList(growable: false);
    if (matches.length != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The installed Candidate could not be matched to exactly one '
            'GGUF model. Reopen Discovery and try again.',
          ),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BenchmarkScreen(
          targetModelId: matches.single.id,
          qualificationArtifactId: artifact.qualificationArtifactId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _surfaceColor,
        elevation: 0,
        title: const Text(
          'Models',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: _accentBlue),
            tooltip: 'Settings',
            onPressed: () => openSettings(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          children: [
            _buildPrivacyNote(),
            const SizedBox(height: 16),
            _buildDiscoveryEntry(),
            const SizedBox(height: 20),
            _buildVerifiedHeading(),
            const SizedBox(height: 10),
            for (final CatalogModel model in kModelCatalog) ...[
              _buildEntry(model),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: _accentBlue),
              SizedBox(width: 8),
              Text(
                'Network use',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Tapping Discover requests public model metadata from Hugging '
            'Face. Tapping Download fetches the selected exact model artifact '
            'from its source repository. Discovery downloads remain '
            'Candidates until they pass the benchmark. Those explicit '
            'actions are the only times this feature uses the network. Your '
            'text, prompts, results and benchmark numbers never leave the '
            'device.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          SizedBox(height: 8),
          Text(
            'Keep the app open while a download runs.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoveryEntry() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.travel_explore_rounded, size: 19, color: _accentBlue),
              SizedBox(width: 8),
              Text(
                'Discover GGUF candidates',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Search recent public, ungated Hugging Face repositories. Opening '
            'the discovery screen is offline; its Discover button starts the '
            'request. Results are candidates, not device-verified models.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            key: const Key('open-gguf-discovery-button'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GgufDiscoveryScreen(
                    onModelInstalled: widget.modelManager.scanModels,
                    onBenchmarkCandidate: _openCandidateBenchmark,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.manage_search_rounded, size: 18),
            label: const Text('Open Discovery'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentBlue,
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifiedHeading() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verified models',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'These bundled entries remain separate from temporary discovery '
          'candidates.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildEntry(CatalogModel model) {
    final _EntryState state = _states[model.id]!;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  model.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              if (state.installed)
                const Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: _successGreen,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Installed',
                      style: TextStyle(color: _successGreen, fontSize: 12),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${model.sizeLabel}  ·  ${model.license}  ·  GGUF',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            model.sourcePage,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          if (state.isDownloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: state.fraction,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(_accentBlue),
              minHeight: 4,
            ),
            const SizedBox(height: 6),
            Text(
              state.progressLabel,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ] else if (state.partialBytes > 0 && !state.installed) ...[
            const SizedBox(height: 8),
            Text(
              'Partial download: ${_formatBytes(state.partialBytes)} of '
              '${model.sizeLabel}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 8),
            Text(
              state.message!,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          _buildActions(model, state),
        ],
      ),
    );
  }

  Widget _buildActions(CatalogModel model, _EntryState state) {
    if (state.installed) {
      return const Text(
        'Already in your models folder.',
        style: TextStyle(color: Colors.white38, fontSize: 12),
      );
    }

    if (state.isDownloading) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => state.cancelToken?.cancel(),
          icon: const Icon(Icons.stop_rounded, size: 18),
          label: const Text('Stop'),
          style: TextButton.styleFrom(foregroundColor: Colors.white70),
        ),
      );
    }

    final bool hasPartial = state.partialBytes > 0;

    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: () => _startDownload(model),
          icon: Icon(
            hasPartial ? Icons.play_arrow_rounded : Icons.download_rounded,
            size: 18,
          ),
          label: Text(hasPartial ? 'Resume' : 'Download'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accentBlue,
            foregroundColor: Colors.black,
          ),
        ),
        if (hasPartial) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => _discard(model),
            style: TextButton.styleFrom(foregroundColor: Colors.white54),
            child: const Text('Discard'),
          ),
        ],
      ],
    );
  }

  static String _formatBytes(int bytes) {
    const int gb = 1000 * 1000 * 1000;
    const int mb = 1000 * 1000;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    return '${(bytes / mb).toStringAsFixed(0)} MB';
  }
}

class _EntryState {
  const _EntryState({
    this.installed = false,
    this.partialBytes = 0,
    this.isDownloading = false,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.message,
    this.cancelToken,
  });

  final bool installed;
  final int partialBytes;
  final bool isDownloading;
  final int receivedBytes;
  final int totalBytes;
  final String? message;
  final DownloadCancelToken? cancelToken;

  double? get fraction {
    if (totalBytes <= 0) return null;
    final double value = receivedBytes / totalBytes;
    return value > 1.0 ? 1.0 : value;
  }

  String get progressLabel {
    final String received = _ModelDownloadScreenState._formatBytes(
      receivedBytes,
    );
    if (totalBytes <= 0) return received;
    final String total = _ModelDownloadScreenState._formatBytes(totalBytes);
    final double pct = (fraction ?? 0) * 100;
    return '$received of $total  ·  ${pct.toStringAsFixed(0)}%';
  }

  _EntryState copyWith({
    bool? installed,
    int? partialBytes,
    bool? isDownloading,
    int? receivedBytes,
    int? totalBytes,
    String? message,
    DownloadCancelToken? cancelToken,
    bool clearCancelToken = false,
  }) {
    return _EntryState(
      installed: installed ?? this.installed,
      partialBytes: partialBytes ?? this.partialBytes,
      isDownloading: isDownloading ?? this.isDownloading,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      message: message,
      cancelToken: clearCancelToken ? null : (cancelToken ?? this.cancelToken),
    );
  }
}
