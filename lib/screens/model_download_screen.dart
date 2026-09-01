import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/benchmark_session.dart';
import '../models/gguf_candidate_assessment.dart';
import '../models/gguf_model_update.dart';
import '../models/model_recommendation.dart';
import '../presentation/model_identity_presentation.dart';
import '../services/database_service.dart';
import '../services/gguf_discovery_cache_service.dart';
import '../services/gguf_install_registry_service.dart';
import '../services/gguf_model_update_service.dart';
import '../services/model_manager_service.dart';
import 'gguf_discovery_screen.dart';
import 'settings_screen.dart';

typedef RecommendationBenchmarkLoader =
    Future<Map<String, Object?>?> Function();

/// Manages the Candidate, Installed, and Recommended model lifecycle.
///
/// Opening this screen performs no network request. Candidate discovery and
/// Candidate downloads remain explicit user actions. Recommended is derived
/// locally from the latest saved Benchmark with at least two successful model
/// comparisons.
class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({
    super.key,
    required this.modelManager,
    this.candidateBuilder,
    this.recommendationLoader,
    this.benchmarkChanges,
    this.installRegistry,
    this.discoveryCache,
    this.updateChecker,
    this.installedModelsOverride,
    this.installedModelsLoadingOverride,
  });

  final ModelManagerService modelManager;

  /// Optional platform-free collaborators for focused widget tests.
  final WidgetBuilder? candidateBuilder;
  final RecommendationBenchmarkLoader? recommendationLoader;
  final ValueListenable<int>? benchmarkChanges;
  final GgufInstallRegistry? installRegistry;
  final GgufDiscoveryCache? discoveryCache;
  final GgufModelUpdateChecker? updateChecker;

  /// Optional installed inventory for focused widget tests.
  final List<ModelInfo>? installedModelsOverride;

  /// Optional initial-scan state for focused widget tests.
  final bool? installedModelsLoadingOverride;

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

enum _ModelsSection { candidates, installed, recommended }

class _ModelsSectionSelector extends StatelessWidget {
  const _ModelsSectionSelector({
    required this.selected,
    required this.onSelected,
  });

  final _ModelsSection selected;
  final ValueChanged<_ModelsSection> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      key: const Key('models-section-selector'),
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: StadiumBorder(side: BorderSide(color: theme.colorScheme.outline)),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _buildSegment(
              context,
              section: _ModelsSection.candidates,
              label: 'Candidates',
              flex: 11,
              showDivider: true,
            ),
            _buildSegment(
              context,
              section: _ModelsSection.installed,
              label: 'Installed',
              flex: 9,
              showDivider: true,
            ),
            _buildSegment(
              context,
              section: _ModelsSection.recommended,
              label: 'Recommended',
              flex: 14,
              showDivider: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegment(
    BuildContext context, {
    required _ModelsSection section,
    required String label,
    required int flex,
    required bool showDivider,
  }) {
    final ThemeData theme = Theme.of(context);
    final bool isSelected = section == selected;
    return Expanded(
      flex: flex,
      child: Semantics(
        button: true,
        selected: isSelected,
        child: InkWell(
          onTap: () => onSelected(section),
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.secondaryContainer
                  : Colors.transparent,
              border: showDivider
                  ? Border(right: BorderSide(color: theme.colorScheme.outline))
                  : null,
            ),
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(
                color: isSelected
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  late final RecommendationBenchmarkLoader _recommendationLoader;
  late final ValueListenable<int> _benchmarkChanges;
  late final GgufInstallRegistry _installRegistry;
  late final GgufDiscoveryCache _discoveryCache;
  late final GgufModelUpdateChecker _updateChecker;
  _ModelsSection _section = _ModelsSection.installed;
  ModelRecommendationSnapshot? _recommendations;
  bool _isLoadingRecommendations = true;
  String? _recommendationError;
  int _recommendationGeneration = 0;
  Map<String, GgufModelUpdateResult> _modelUpdates =
      <String, GgufModelUpdateResult>{};
  bool _isCheckingUpdates = false;
  String? _updateCheckMessage;
  int _updateCheckGeneration = 0;

  List<ModelInfo> get _installedModels =>
      widget.installedModelsOverride ?? widget.modelManager.summarizerModels;

  bool get _isInstalledInventoryLoading =>
      widget.installedModelsLoadingOverride ??
      (widget.installedModelsOverride == null &&
          widget.modelManager.isLoading &&
          _installedModels.isEmpty);

  @override
  void initState() {
    super.initState();
    _recommendationLoader =
        widget.recommendationLoader ??
        DatabaseService.instance.getLatestRecommendationBenchmark;
    _benchmarkChanges =
        widget.benchmarkChanges ?? DatabaseService.instance.benchmarkChanges;
    _installRegistry = widget.installRegistry ?? GgufInstallRegistryService();
    _discoveryCache = widget.discoveryCache ?? GgufDiscoveryCacheService();
    _updateChecker = widget.updateChecker ?? GgufModelUpdateService();
    widget.modelManager.addListener(_onModelManagerChanged);
    _benchmarkChanges.addListener(_onBenchmarkChanged);
    unawaited(_loadRecommendations());
  }

  void _onModelManagerChanged() {
    if (mounted) setState(() {});
  }

  void _onBenchmarkChanged() {
    unawaited(_loadRecommendations());
  }

  @override
  void dispose() {
    widget.modelManager.removeListener(_onModelManagerChanged);
    _benchmarkChanges.removeListener(_onBenchmarkChanged);
    super.dispose();
  }

  Future<void> _loadRecommendations() async {
    final int generation = ++_recommendationGeneration;
    if (mounted) {
      setState(() {
        _isLoadingRecommendations = true;
        _recommendationError = null;
      });
    }

    try {
      final Map<String, Object?>? saved = await _recommendationLoader();
      final ModelRecommendationSnapshot? snapshot = saved == null
          ? null
          : buildModelRecommendationSnapshot(saved);
      if (!mounted || generation != _recommendationGeneration) return;
      setState(() {
        _recommendations = snapshot;
        _isLoadingRecommendations = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _recommendationGeneration) return;
      setState(() {
        _recommendations = null;
        _isLoadingRecommendations = false;
        _recommendationError = 'Could not load recommendations: $error';
      });
    }
  }

  Future<void> _checkForUpdates() async {
    if (_isCheckingUpdates) return;
    final int generation = ++_updateCheckGeneration;
    final List<ModelInfo> ggufModels = _installedModels
        .where((ModelInfo model) => model.engine == ModelEngine.gguf)
        .toList(growable: false);
    setState(() {
      _isCheckingUpdates = true;
      _updateCheckMessage = null;
      _modelUpdates = <String, GgufModelUpdateResult>{};
    });

    try {
      final List<GgufCandidateArtifact> saved = List<GgufCandidateArtifact>.of(
        await _installRegistry.load(),
      );
      final Map<String, GgufCandidateArtifact> byFileName =
          <String, GgufCandidateArtifact>{
            for (final GgufCandidateArtifact artifact in saved)
              artifact.fileName.toLowerCase(): artifact,
          };
      List<GgufCandidateArtifact>? cachedCandidates;
      final Map<String, GgufModelUpdateResult> results =
          <String, GgufModelUpdateResult>{};
      int adoptedCount = 0;
      int registryFailures = 0;

      for (int index = 0; index < ggufModels.length; index++) {
        if (!mounted || generation != _updateCheckGeneration) return;
        final ModelInfo model = ggufModels[index];
        setState(() {
          _updateCheckMessage =
              'Checking model ${index + 1} of ${ggufModels.length}…';
        });
        GgufCandidateArtifact? artifact = byFileName[model.name.toLowerCase()];
        bool localIdentityAlreadyVerified = false;

        if (artifact == null) {
          if (cachedCandidates == null) {
            final GgufDiscoveryCacheEntry? cacheEntry = await _discoveryCache
                .load();
            cachedCandidates =
                cacheEntry?.result.assessments
                    .map((assessment) => assessment.artifact)
                    .whereType<GgufCandidateArtifact>()
                    .toList(growable: false) ??
                <GgufCandidateArtifact>[];
          }
          artifact = await _updateChecker.recognizeInstalledArtifact(
            installedPath: model.path,
            candidates: cachedCandidates,
          );
          if (artifact != null) {
            if (await _installRegistry.record(artifact)) {
              byFileName[artifact.fileName.toLowerCase()] = artifact;
              adoptedCount++;
              localIdentityAlreadyVerified = true;
            } else {
              registryFailures++;
              artifact = null;
            }
          }
        }

        if (artifact == null) continue;
        results[model.id] = await _updateChecker.check(
          installedArtifact: artifact,
          installedPath: model.path,
          localIdentityAlreadyVerified: localIdentityAlreadyVerified,
        );
      }

      if (!mounted || generation != _updateCheckGeneration) return;
      final int updateCount = results.values
          .where((GgufModelUpdateResult result) => result.hasUpdate)
          .length;
      final int unavailableCount = results.values
          .where(
            (GgufModelUpdateResult result) =>
                result.status == GgufModelUpdateStatus.unavailable ||
                result.status == GgufModelUpdateStatus.localFileChanged,
          )
          .length;
      final String adoptedArtifactLabel = adoptedCount == 1
          ? 'artifact'
          : 'artifacts';
      final String adoptionSuffix = adoptedCount == 0
          ? ''
          : ' Recognized $adoptedCount existing exact '
                '$adoptedArtifactLabel.';
      final String message;
      if (results.isEmpty) {
        message = registryFailures == 0
            ? 'No update-managed GGUF models were found.'
            : 'Update source information could not be saved.';
      } else if (updateCount > 0) {
        final String unavailableSuffix = unavailableCount == 0
            ? ''
            : ' $unavailableCount could not be confirmed.';
        message =
            '$updateCount ${updateCount == 1 ? 'update' : 'updates'} '
            'available.$unavailableSuffix$adoptionSuffix';
      } else if (unavailableCount > 0) {
        final String modelLabel = results.length == 1 ? 'model' : 'models';
        message =
            'Checked ${results.length} $modelLabel; '
            '$unavailableCount could not be confirmed.$adoptionSuffix';
      } else {
        final String modelVerb = results.length == 1
            ? 'model is'
            : 'models are';
        message =
            '${results.length} $modelVerb up to date.'
            '$adoptionSuffix';
      }
      setState(() {
        _modelUpdates = results;
        _updateCheckMessage = message;
        _isCheckingUpdates = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _updateCheckGeneration) return;
      setState(() {
        _isCheckingUpdates = false;
        _updateCheckMessage = 'Could not check for updates: $error';
      });
    }
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
              'Discover, manage, and compare',
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
              child: _ModelsSectionSelector(
                selected: _section,
                onSelected: (_ModelsSection selected) {
                  setState(() => _section = selected);
                  if (selected == _ModelsSection.recommended) {
                    unawaited(_loadRecommendations());
                  }
                },
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _section.index,
                children: [
                  _buildCandidatesSection(),
                  _buildInstalledSection(),
                  _buildRecommendedSection(),
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
      discoveryCache: _discoveryCache,
      installRegistry: _installRegistry,
      onModelInstalled: widget.modelManager.scanModels,
    );
  }

  Widget _buildInstalledSection() {
    final List<ModelInfo> models = _installedModels;
    final bool isLoading = models.isEmpty && _isInstalledInventoryLoading;
    final Map<String, String> displayNames = resolveConciseModelNames(
      models.map(
        (ModelInfo model) => ModelDisplayIdentity(
          key: model.id,
          technicalName: model.name,
          engine: model.engine,
        ),
      ),
    );
    return ListView(
      key: const PageStorageKey<String>('installed-models-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (isLoading)
          _buildInstalledScanningState()
        else ...[
          _buildInstalledSummary(models),
          const SizedBox(height: 16),
          if (models.isEmpty)
            _buildNoInstalledModels()
          else
            for (final ModelInfo model in models) ...[
              _buildInstalledModelCard(model, displayNames[model.id]!),
              const SizedBox(height: 12),
            ],
        ],
      ],
    );
  }

  Widget _buildInstalledScanningState() {
    final ThemeData theme = Theme.of(context);
    return Card(
      key: const Key('installed-models-scanning'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scanning for models…',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Checking system and downloaded models on this device.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
            const SizedBox(height: 14),
            FilledButton.tonalIcon(
              key: const Key('check-model-updates'),
              onPressed: _isCheckingUpdates ? null : _checkForUpdates,
              icon: _isCheckingUpdates
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update_alt_rounded),
              label: Text(
                _isCheckingUpdates
                    ? 'Checking for updates…'
                    : 'Check for updates',
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Checks saved sources for app-downloaded GGUF models only.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            if (_updateCheckMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _updateCheckMessage!,
                key: const Key('model-update-summary'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
                  'Rescan the device or download a Candidate.',
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

  Widget _buildInstalledModelCard(ModelInfo model, String displayName) {
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
                      Text(displayName, style: theme.textTheme.titleMedium),
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
                ModelRuntimeBadge(engine: model.engine),
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
            if (_modelUpdates[model.id] != null) ...[
              const SizedBox(height: 12),
              _buildModelUpdateStatus(_modelUpdates[model.id]!),
            ],
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

  Widget _buildModelUpdateStatus(GgufModelUpdateResult update) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final (IconData, String, Color) presentation = switch (update.status) {
      GgufModelUpdateStatus.upToDate => (
        Icons.cloud_done_outlined,
        'Up to date',
        colors.primary,
      ),
      GgufModelUpdateStatus.updateAvailable => (
        Icons.system_update_alt_rounded,
        'Update available',
        colors.tertiary,
      ),
      GgufModelUpdateStatus.localFileChanged => (
        Icons.warning_amber_rounded,
        'Local file could not be verified',
        colors.error,
      ),
      GgufModelUpdateStatus.unavailable => (
        Icons.cloud_off_outlined,
        'Update check unavailable',
        colors.error,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(presentation.$1, size: 20, color: presentation.$3),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                presentation.$2,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: presentation.$3,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          update.message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        if (update.hasUpdate) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            key: ValueKey<String>(
              'review-model-update-${update.installedArtifact.fileName}',
            ),
            onPressed: () => _showUpdateReview(update),
            icon: const Icon(Icons.compare_arrows_rounded),
            label: const Text('Review update'),
          ),
        ],
      ],
    );
  }

  Widget _buildRecommendedSection() {
    final List<RecommendedModel> models =
        _recommendations?.models ?? const <RecommendedModel>[];
    final Map<String, String> displayNames = resolveConciseModelNames(
      models.map(
        (RecommendedModel model) => ModelDisplayIdentity(
          key: model.modelId,
          technicalName: model.modelName,
          engine: model.engine,
        ),
      ),
    );
    return ListView(
      key: const PageStorageKey<String>('recommended-models-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _buildRecommendationExplanation(),
        const SizedBox(height: 16),
        if (_isLoadingRecommendations)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_recommendationError != null)
          _buildRecommendationError(_recommendationError!)
        else if (_recommendations == null)
          _buildNoRecommendations()
        else ...[
          _buildRecommendationEvidence(_recommendations!),
          const SizedBox(height: 16),
          for (final RecommendedModel model in models) ...[
            _buildRecommendedModelCard(model, displayNames[model.modelId]!),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }

  Widget _buildRecommendationExplanation() {
    final ThemeData theme = Theme.of(context);
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
                Icon(
                  Icons.workspace_premium_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Measured strengths',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Recommendations come from the most recent completed Benchmark '
              'that compared at least two models. They update after a newer '
              'qualifying Benchmark and never combine metrics into one score.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoRecommendations() {
    final ThemeData theme = Theme.of(context);
    return Card(
      key: const Key('no-model-recommendations'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('No recommendations yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Run a Benchmark with at least two installed models. Recall and '
              'performance are compared for every successful test; structured '
              'length compliance is also compared when applicable.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationError(String message) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendationEvidence(ModelRecommendationSnapshot snapshot) {
    final ThemeData theme = Theme.of(context);
    final String runs = snapshot.runsPerModel == 1 ? 'run' : 'runs';
    return Card(
      key: const Key('recommendation-evidence'),
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              snapshot.taskLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${snapshot.comparedModelCount} models · '
              '${snapshot.runsPerModel} $runs per model',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              formatBenchmarkDateTime(snapshot.completedAt.toLocal()),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendedModelCard(
    RecommendedModel model,
    String displayName,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool installed = _installedModels.any(
      (ModelInfo available) => available.id == model.modelId,
    );

    return Card(
      key: ValueKey<String>('recommended-model-${model.modelId}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  displayName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                ModelRuntimeBadge(engine: model.engine),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              installed
                  ? 'Installed on this device'
                  : 'Not currently installed',
              style: theme.textTheme.bodySmall?.copyWith(
                color: installed ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            for (final ModelRecommendationStrength strength
                in model.strengths) ...[
              _buildStrengthRow(strength),
              if (strength != model.strengths.last) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStrengthRow(ModelRecommendationStrength strength) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _recommendationIcon(strength.metric),
          size: 20,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strength.metric.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                strength.valueLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  IconData _recommendationIcon(ModelRecommendationMetric metric) =>
      switch (metric) {
        ModelRecommendationMetric.recall => Icons.fact_check_outlined,
        ModelRecommendationMetric.lengthCompliance =>
          Icons.format_list_numbered_rounded,
        ModelRecommendationMetric.latency => Icons.timer_outlined,
        ModelRecommendationMetric.ttft => Icons.first_page_rounded,
        ModelRecommendationMetric.generationSpeed => Icons.speed_rounded,
      };

  IconData _engineIcon(ModelEngine engine) => switch (engine) {
    ModelEngine.nano => Icons.auto_awesome_outlined,
    ModelEngine.gguf => Icons.memory_outlined,
    ModelEngine.litertlm => Icons.developer_board_outlined,
    ModelEngine.mediapipe => Icons.memory_outlined,
  };

  String _installedDescription(ModelInfo model) => switch (model.engine) {
    ModelEngine.nano => 'System-managed · Available offline',
    ModelEngine.gguf => '${model.formattedSize} · Stored on this device',
    ModelEngine.litertlm =>
      '${model.formattedSize} · Sideloaded prototype · GPU backend',
    ModelEngine.mediapipe =>
      '${model.formattedSize} · MediaPipe model · No longer supported',
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
            _buildDetailRow('Engine', modelRuntimeLabel(model.engine)),
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

  Future<void> _showUpdateReview(GgufModelUpdateResult update) {
    final GgufCandidateArtifact? remote = update.remoteArtifact;
    if (remote == null) return Future<void>.value();
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Review update'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current installed artifact',
                style: Theme.of(dialogContext).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              _buildArtifactDetails(update.installedArtifact),
              const Divider(height: 28),
              Text(
                'Current remote artifact',
                style: Theme.of(dialogContext).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              _buildArtifactDetails(remote),
              const SizedBox(height: 8),
              Text(
                'This review does not download or replace either file.',
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
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

  Widget _buildArtifactDetails(GgufCandidateArtifact artifact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSelectableDetailRow('Repository', artifact.repositoryId),
        _buildSelectableDetailRow('Filename', artifact.fileName),
        _buildSelectableDetailRow(
          'File size',
          _formatBytes(artifact.sizeBytes),
        ),
        _buildSelectableDetailRow('Commit / revision', artifact.commitSha),
        _buildSelectableDetailRow('SHA-256', artifact.sha256),
      ],
    );
  }

  Widget _buildSelectableDetailRow(String label, String value) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
          SelectableText(value, style: theme.textTheme.bodyMedium),
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
    bool registryCleared = true;
    if (removed && model.engine == ModelEngine.gguf) {
      registryCleared = await _installRegistry.remove(model.name);
      _modelUpdates.remove(model.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed
              ? registryCleared
                    ? 'Removed ${model.name}.'
                    : 'Removed ${model.name}, but its saved update source '
                          'could not be cleared.'
              : widget.modelManager.statusMessage ??
                    'Could not remove the model.',
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    const int gb = 1000 * 1000 * 1000;
    const int mb = 1000 * 1000;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    return '${(bytes / mb).toStringAsFixed(0)} MB';
  }
}
