import 'package:flutter/material.dart';

import '../models/model_catalog.dart';
import '../services/model_download_service.dart';
import '../services/model_manager_service.dart';
import 'gguf_discovery_screen.dart';
import 'settings_screen.dart';

/// Manages installed models, the verified catalog, and GGUF discovery.
///
/// Opening this screen is offline. Installed-state checks and cached Candidate
/// restoration are local; only explicit Discover and Download actions use the
/// network.
class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({
    super.key,
    required this.modelManager,
    this.downloadService,
    this.candidateBuilder,
  });

  final ModelManagerService modelManager;

  /// Optional platform-free collaborators for focused widget tests.
  final ModelDownloadService? downloadService;
  final WidgetBuilder? candidateBuilder;

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

enum _ModelsSection { installed, verified, candidates }

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  late final ModelDownloadService _downloader;
  final Map<String, _EntryState> _states = <String, _EntryState>{};
  _ModelsSection _section = _ModelsSection.installed;

  @override
  void initState() {
    super.initState();
    _downloader = widget.downloadService ?? ModelDownloadService();
    for (final CatalogModel model in kModelCatalog) {
      _states[model.id] = const _EntryState();
    }
    widget.modelManager.addListener(_onModelManagerChanged);
    _refreshAll();
  }

  void _onModelManagerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.modelManager.removeListener(_onModelManagerChanged);
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
    if (result.isSuccess) await widget.modelManager.scanModels();
    if (!mounted) return;

    final String? note = _messageFor(result);
    if (note != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
    }
  }

  String? _messageFor(DownloadResult result) {
    return switch (result.outcome) {
      DownloadOutcome.completed =>
        'Installed. It will appear in the model picker.',
      DownloadOutcome.cancelled =>
        'Stopped. Partial file kept — Resume picks up where it left off.',
      DownloadOutcome.networkError =>
        'Download failed: ${result.message ?? 'network error'}. Partial file kept.',
      DownloadOutcome.checksumFailed =>
        'Checksum did not match. The file was discarded, not installed.',
      DownloadOutcome.storageError =>
        'Storage error: ${result.message ?? 'could not write the file'}.',
      DownloadOutcome.fileConflict =>
        'A different file already uses this model filename. It was not changed.',
    };
  }

  Future<void> _discard(CatalogModel model) async {
    await _downloader.discardPartial(model.fileName);
    if (!mounted) return;
    setState(() {
      _states[model.id] = _states[model.id]!.copyWith(message: null);
    });
    await _refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 82,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Models',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Manage local inference models',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => openSettings(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<_ModelsSection>(
                  key: const Key('models-section-selector'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: _ModelsSection.installed,
                      label: Text('Installed'),
                    ),
                    ButtonSegment(
                      value: _ModelsSection.verified,
                      label: Text('Verified'),
                    ),
                    ButtonSegment(
                      value: _ModelsSection.candidates,
                      label: Text('Candidates'),
                    ),
                  ],
                  selected: {_section},
                  onSelectionChanged: (Set<_ModelsSection> selected) {
                    setState(() => _section = selected.single);
                  },
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _section.index,
                children: [
                  _buildInstalledSection(),
                  _buildVerifiedSection(),
                  _buildCandidatesSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCandidatesSection() {
    final WidgetBuilder? builder = widget.candidateBuilder;
    if (builder != null) return builder(context);
    return GgufDiscoveryScreen(
      embedded: true,
      onModelInstalled: () async {
        await widget.modelManager.scanModels();
        await _refreshAll();
      },
    );
  }

  Widget _buildInstalledSection() {
    final List<ModelInfo> models = widget.modelManager.summarizerModels;
    return ListView(
      key: const PageStorageKey<String>('installed-models-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _buildInstalledSummary(models),
        const SizedBox(height: 16),
        if (models.isEmpty)
          _buildNoInstalledModels()
        else
          for (final ModelInfo model in models) ...[
            _buildInstalledModelCard(model),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _buildInstalledSummary(List<ModelInfo> models) {
    final ThemeData theme = Theme.of(context);
    final int totalBytes = models.fold(
      0,
      (int total, ModelInfo model) => total + model.sizeBytes,
    );
    final String countLabel = models.length == 1 ? 'model' : 'models';
    final String storageLabel = totalBytes == 0
        ? 'System-managed models'
        : 'System and downloaded models · approximately '
              '${_formatBytes(totalBytes)}';

    return Card(
      key: const Key('installed-models-summary'),
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.storage_outlined,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${models.length} $countLabel available on this device',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    storageLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoInstalledModels() {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No models found', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              widget.modelManager.statusMessage ??
                  'Rescan the device or install a verified model.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: widget.modelManager.isLoading
                  ? null
                  : widget.modelManager.scanModels,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Rescan models'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstalledModelCard(ModelInfo model) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Color readyColor = theme.brightness == Brightness.dark
        ? const Color(0xFF81C784)
        : const Color(0xFF2E7D32);

    return Card(
      key: ValueKey<String>('installed-model-${model.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _engineIcon(model.engine),
                    color: colors.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(model.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        _installedDescription(model),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildEngineBadge(model.engine),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.check_circle_outline, size: 20, color: readyColor),
                const SizedBox(width: 8),
                Text(
                  'Ready',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: readyColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => _showModelDetails(model),
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Details'),
                ),
                if (model.engine != ModelEngine.nano)
                  TextButton.icon(
                    onPressed: widget.modelManager.isLoading
                        ? null
                        : () => _confirmDeleteModel(model),
                    style: TextButton.styleFrom(foregroundColor: colors.error),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineBadge(ModelEngine engine) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _engineLabel(engine),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _engineLabel(ModelEngine engine) => switch (engine) {
    ModelEngine.nano => 'AICore',
    ModelEngine.gguf => 'GGUF',
    ModelEngine.litertlm => 'LiteRT-LM',
    ModelEngine.mediapipe => 'Legacy',
  };

  IconData _engineIcon(ModelEngine engine) => switch (engine) {
    ModelEngine.nano => Icons.auto_awesome_outlined,
    ModelEngine.gguf => Icons.memory_outlined,
    ModelEngine.litertlm => Icons.developer_board_outlined,
    ModelEngine.mediapipe => Icons.memory_outlined,
  };

  String _installedDescription(ModelInfo model) => switch (model.engine) {
    ModelEngine.nano => 'System-managed · Available offline',
    ModelEngine.gguf => '${model.formattedSize} · Local GGUF model',
    ModelEngine.litertlm =>
      '${model.formattedSize} · Sideloaded prototype · GPU backend',
    ModelEngine.mediapipe => '${model.formattedSize} · Legacy local model',
  };

  Future<void> _showModelDetails(ModelInfo model) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(model.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Engine', _engineLabel(model.engine)),
            _buildDetailRow('Size', model.formattedSize),
            _buildDetailRow('Prompt format', model.promptFormat.label),
            _buildDetailRow(
              'Storage',
              model.engine == ModelEngine.nano
                  ? 'Managed by Android AICore'
                  : 'App-local model storage',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteModel(ModelInfo model) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Remove model file?'),
        content: Text(
          '${model.name} (${model.formattedSize}) will be deleted from your '
          'device. Saved summaries and benchmark sessions are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirm-remove-installed-model'),
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final bool removed = await widget.modelManager.deleteModel(model);
    await _refreshAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed
              ? 'Removed ${model.name}.'
              : widget.modelManager.statusMessage ??
                    'Could not remove the model.',
        ),
      ),
    );
  }

  Widget _buildVerifiedSection() {
    return ListView(
      key: const PageStorageKey<String>('verified-models-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _buildPrivacyNote(),
        const SizedBox(height: 20),
        _buildVerifiedHeading(),
        const SizedBox(height: 10),
        for (final CatalogModel model in kModelCatalog) ...[
          _buildEntry(model),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildPrivacyNote() {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Network use', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Downloading here fetches only the Verified model artifact you '
              'select. Candidate discovery and downloads remain separate '
              'explicit actions in Candidates. Your text, prompts, results, '
              'and benchmark numbers remain on this device.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Keep the app open while a download runs.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerifiedHeading() {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Verified models', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Curated artifacts with fixed source and checksum metadata.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildEntry(CatalogModel model) {
    final _EntryState state = _states[model.id]!;
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Card(
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
                    model.displayName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (state.installed)
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Installed',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${model.sizeLabel} · ${model.license} · GGUF',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              model.sourcePage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            if (state.isDownloading) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: state.fraction,
                color: colors.primary,
                minHeight: 4,
              ),
              const SizedBox(height: 6),
              Text(state.progressLabel, style: theme.textTheme.bodySmall),
            ] else if (state.partialBytes > 0 && !state.installed) ...[
              const SizedBox(height: 8),
              Text(
                'Partial download: ${_formatBytes(state.partialBytes)} of '
                '${model.sizeLabel}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (state.message != null) ...[
              const SizedBox(height: 8),
              Text(state.message!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            _buildActions(model, state),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(CatalogModel model, _EntryState state) {
    if (state.installed) {
      return Text(
        'Already in your models folder.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    if (state.isDownloading) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => state.cancelToken?.cancel(),
          icon: const Icon(Icons.stop_rounded, size: 18),
          label: const Text('Stop'),
        ),
      );
    }

    final bool hasPartial = state.partialBytes > 0;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: () => _startDownload(model),
          icon: Icon(
            hasPartial ? Icons.play_arrow_rounded : Icons.download_rounded,
            size: 18,
          ),
          label: Text(hasPartial ? 'Resume' : 'Download'),
        ),
        if (hasPartial)
          TextButton(
            onPressed: () => _discard(model),
            child: const Text('Discard'),
          ),
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
    return '$received of $total · ${pct.toStringAsFixed(0)}%';
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
