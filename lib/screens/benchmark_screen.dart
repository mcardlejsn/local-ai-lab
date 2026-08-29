import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/benchmark_session.dart';
import '../models/recall_checklist.dart';
import '../services/database_service.dart';
import '../services/gemini_nano_service.dart';
import '../services/llama_gguf_service.dart';
import '../services/model_manager_service.dart';
import '../widgets/benchmark_results_table.dart';
import 'saved_benchmark_sessions_screen.dart';
import 'settings_screen.dart';

// The result classes moved to lib/models/benchmark_session.dart so the archive
// screens can share them. Re-exported here so existing imports of this file
// continue to resolve them.
export '../models/benchmark_session.dart'
    show BenchmarkModelResult, BenchmarkAggregate;

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({
    super.key,
    this.targetModelId,
    this.qualificationArtifactId,
    this.modelManager,
    this.initializeOnInit = true,
  }) : assert(
         (targetModelId == null) == (qualificationArtifactId == null),
         'Candidate target and exact artifact identity must be supplied '
         'together.',
       );

  /// When set, the benchmark runs only this exact installed GGUF model.
  ///
  /// Ordinary navigation leaves this null and retains the existing all-model
  /// comparison suite.
  final String? targetModelId;

  /// Exact Discovery artifact associated with a single-model benchmark run.
  final String? qualificationArtifactId;

  /// Shares the existing singleton in production while allowing focused
  /// widget tests to render without starting platform model discovery.
  final ModelManagerService? modelManager;

  final bool initializeOnInit;

  bool get isCandidateQualification => targetModelId != null;

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

/// Returns the models that belong in the current benchmark run.
///
/// A Candidate single-model benchmark is deliberately limited to the exact
/// GGUF path selected from Discovery. A normal suite may filter the available
/// models by the user's screen-local selection. Omitting [selectedModelIds]
/// preserves the original all-model behavior.
List<ModelInfo> benchmarkModelsForTarget(
  List<ModelInfo> availableModels, {
  String? targetModelId,
  Set<String>? selectedModelIds,
}) {
  if (targetModelId != null) {
    return List<ModelInfo>.unmodifiable(
      availableModels.where(
        (ModelInfo model) =>
            model.id == targetModelId && model.engine == ModelEngine.gguf,
      ),
    );
  }

  if (selectedModelIds == null) {
    return List<ModelInfo>.unmodifiable(availableModels);
  }

  return List<ModelInfo>.unmodifiable(
    availableModels.where(
      (ModelInfo model) => selectedModelIds.contains(model.id),
    ),
  );
}

/// A Candidate single-model benchmark needs its one exact target. The ordinary
/// comparison suite intentionally requires at least two selected models.
bool canRunBenchmarkModels(
  List<ModelInfo> models, {
  required bool isCandidateQualification,
}) {
  return isCandidateQualification ? models.isNotEmpty : models.length >= 2;
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  late final ModelManagerService _modelManager;
  final TextEditingController _promptController = TextEditingController(
    text: defaultBenchmarkPassage,
  );
  final TextEditingController _instructionController = TextEditingController(
    text: defaultBenchmarkInstruction,
  );

  final List<BenchmarkAggregate> _aggregates = [];
  final Set<String> _selectedModelIds = <String>{};
  int _runsPerModel = 3;
  bool _isRunning = false;
  bool _isRestoring = true;
  bool _hasRestoredSession = false;
  bool _hasInitializedModelSelection = false;
  bool _isEditingTestCase = false;
  int _currentRunningIndex = -1;
  int _currentRunNumber = 0;
  String _currentStatus = 'Ready to benchmark.';

  @override
  void initState() {
    super.initState();
    _modelManager = widget.modelManager ?? ModelManagerService();
    if (widget.isCandidateQualification) {
      _currentStatus = 'Finding the installed model...';
    }
    _modelManager.addListener(_onModelManagerStateChanged);
    // The picker's selection is derived from the passage text, so edits typed
    // straight into the field have to redraw it.
    _promptController.addListener(_onPassageTextChanged);
    if (widget.initializeOnInit) {
      _initializeScreen();
    } else {
      _isRestoring = false;
    }
  }

  void _onPassageTextChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initializeScreen() async {
    if (!widget.isCandidateQualification) {
      try {
        await _restoreLatestBenchmark();
      } catch (e) {
        if (mounted) {
          setState(() {
            _currentStatus = 'Could not restore the latest benchmark: $e';
          });
        }
      }
    }

    if (mounted) {
      setState(() {
        _isRestoring = false;
      });
    }

    if (mounted) {
      await _modelManager.scanModels();
    }
  }

  Future<void> _restoreLatestBenchmark() async {
    final saved = await DatabaseService.instance.getLatestCompletedBenchmark(
      comparisonOnly: true,
    );
    if (saved == null || !mounted) return;

    final runMaps = (saved['runs'] as List).cast<Map<String, Object?>>();
    final restored = buildAggregatesFromSavedRuns(runMaps);
    final completedAt = DateTime.parse(
      saved['completed_at'] as String,
    ).toLocal();

    setState(() {
      _promptController.text = saved['passage'] as String;
      _instructionController.text = saved['instruction'] as String;
      _runsPerModel = saved['runs_per_model'] as int;
      _aggregates
        ..clear()
        ..addAll(restored);
      _hasRestoredSession = true;
      _currentStatus =
          'Restored benchmark completed '
          '${formatBenchmarkDateTime(completedAt)}.';
    });
  }

  /// Re-reads the session that was just saved, so the table shows the recall
  /// grades written at save time without confusing it with another run type.
  Future<void> _reloadSavedRuns(int sessionId) async {
    final saved = await DatabaseService.instance.getCompletedBenchmarkById(
      sessionId,
    );
    if (saved == null || !mounted) return;

    final runMaps = (saved['runs'] as List).cast<Map<String, Object?>>();
    final restored = buildAggregatesFromSavedRuns(runMaps);

    setState(() {
      _aggregates
        ..clear()
        ..addAll(restored);
    });
  }

  Future<void> _openSavedSessions() async {
    if (_isRunning || _isRestoring) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SavedBenchmarkSessionsScreen()),
    );
  }

  @override
  void dispose() {
    _modelManager.removeListener(_onModelManagerStateChanged);
    _promptController.removeListener(_onPassageTextChanged);
    _promptController.dispose();
    _instructionController.dispose();
    super.dispose();
  }

  void _onModelManagerStateChanged() {
    if (mounted) {
      setState(() {
        final List<ModelInfo> availableModels = benchmarkModelsForTarget(
          _modelManager.availableModels,
          targetModelId: widget.targetModelId,
        );

        if (!widget.isCandidateQualification &&
            !_modelManager.isLoading &&
            availableModels.isNotEmpty) {
          final Set<String> availableIds = availableModels
              .map((ModelInfo model) => model.id)
              .toSet();
          if (!_hasInitializedModelSelection) {
            _selectedModelIds
              ..clear()
              ..addAll(availableIds);
            _hasInitializedModelSelection = true;
          } else {
            _selectedModelIds.retainAll(availableIds);
          }
        }

        if (!_isRunning && !_isRestoring && !_hasRestoredSession) {
          final List<ModelInfo> models = benchmarkModelsForTarget(
            _modelManager.availableModels,
            targetModelId: widget.targetModelId,
            selectedModelIds: widget.isCandidateQualification
                ? null
                : _selectedModelIds,
          );
          if (availableModels.isEmpty) {
            _currentStatus = widget.isCandidateQualification
                ? 'The selected model is no longer installed.'
                : 'No models found to benchmark.';
          } else if (widget.isCandidateQualification) {
            _currentStatus =
                'Installed model ready to benchmark: ${models.single.name}';
          } else if (availableModels.length < 2) {
            _currentStatus =
                'At least 2 installed models are required for comparison.';
          } else {
            _currentStatus =
                '${models.length} of ${availableModels.length} models selected.';
          }
        }
      });
    }
  }

  void _setModelSelected(String modelId, bool selected) {
    if (_isRunning || _isRestoring || _modelManager.isLoading) return;

    setState(() {
      if (selected) {
        _selectedModelIds.add(modelId);
      } else {
        _selectedModelIds.remove(modelId);
      }
      _currentStatus = _selectedModelIds.length < 2
          ? 'Select at least 2 models to run the comparison suite.'
          : '${_selectedModelIds.length} models selected for comparison.';
    });
  }

  void _selectAllModels(List<ModelInfo> availableModels) {
    if (_isRunning || _isRestoring || _modelManager.isLoading) return;

    setState(() {
      _selectedModelIds
        ..clear()
        ..addAll(availableModels.map((ModelInfo model) => model.id));
      _currentStatus =
          'All ${availableModels.length} models selected for comparison.';
    });
  }

  Future<void> _runBenchmarkSuite() async {
    final List<ModelInfo> models = benchmarkModelsForTarget(
      _modelManager.availableModels,
      targetModelId: widget.targetModelId,
      selectedModelIds: widget.isCandidateQualification
          ? null
          : _selectedModelIds,
    );
    if (_isRunning ||
        !canRunBenchmarkModels(
          models,
          isCandidateQualification: widget.isCandidateQualification,
        )) {
      return;
    }

    setState(() {
      _isRunning = true;
      _isEditingTestCase = false;
      _hasRestoredSession = false;
      _currentRunningIndex = 0;
      _currentRunNumber = 1;
      _aggregates.clear();
    });

    final String rawText = _promptController.text.trim();
    final String instruction = _instructionController.text.trim();
    final int runsPerModel = _runsPerModel;

    for (int i = 0; i < models.length; i++) {
      if (!mounted) return;

      final model = models[i];
      final aggregate = BenchmarkAggregate(
        modelId: model.id,
        modelName: model.name,
        modelPath: model.path,
        engine: model.engine,
        promptFormat: model.promptFormat,
      );

      setState(() {
        _currentRunningIndex = i;
        _aggregates.add(aggregate);
      });

      final fullPrompt = buildInferencePrompt(
        format: model.promptFormat,
        instruction: instruction,
        rawText: rawText,
      );

      for (int run = 0; run < runsPerModel; run++) {
        if (!mounted) return;

        setState(() {
          _currentRunNumber = run + 1;
          _currentStatus =
              'Benchmarking (${i + 1}/${models.length}) run ${run + 1}/$runsPerModel: ${model.name}...';
        });

        await Future.delayed(const Duration(milliseconds: 250));

        final result = await _executeSingleBenchmark(model, fullPrompt);

        if (!mounted) return;
        setState(() {
          aggregate.runs.add(result);
        });
      }
    }

    String? saveError;
    try {
      final int sessionId = await _saveCompletedBenchmark(
        passage: rawText,
        instruction: instruction,
        runsPerModel: runsPerModel,
      );
      // Re-read what was just written so the displayed runs carry their
      // stored recall grades.
      await _reloadSavedRuns(sessionId);
    } catch (e) {
      saveError = e.toString();
    }

    if (mounted) {
      setState(() {
        _isRunning = false;
        _hasRestoredSession = saveError == null;
        _currentRunningIndex = -1;
        _currentRunNumber = 0;
        if (saveError == null) {
          _currentStatus = widget.isCandidateQualification
              ? 'Single-model benchmark completed and saved: '
                    '$runsPerModel ${runsPerModel == 1 ? 'run' : 'runs'}.'
              : 'Benchmark suite completed and saved: '
                    '${_aggregates.length} models × $runsPerModel runs.';
        } else {
          _currentStatus = widget.isCandidateQualification
              ? 'Single-model benchmark completed, but the session could not '
                    'be saved: $saveError'
              : 'Benchmark suite completed, but the grouped session '
                    'could not be saved: $saveError';
        }
      });
    }

    // Restore the model the user has selected. The suite leaves its last GGUF
    // model resident, so loadModel also cleans that runtime up before restoring
    // the user's selection.
    final selectedModel = _modelManager.activeModel;
    if (selectedModel == null) {
      await _modelManager.unloadAllEngines();
    } else {
      await _modelManager.loadModel(selectedModel);
    }
  }

  Future<int> _saveCompletedBenchmark({
    required String passage,
    required String instruction,
    required int runsPerModel,
  }) async {
    final runRows = <Map<String, Object?>>[];

    // Recall is graded against the content of whatever passage was run, so a
    // custom passage grades the same way the built-in one does. An empty
    // passage has no content to expect, so the columns stay null rather than
    // recording a score of zero.
    final profile = profileForPassage(passage);

    for (int modelOrder = 0; modelOrder < _aggregates.length; modelOrder++) {
      final aggregate = _aggregates[modelOrder];
      for (int runIndex = 0; runIndex < aggregate.runs.length; runIndex++) {
        final run = aggregate.runs[runIndex];
        final recall = (profile.isEmpty || run.errorMessage != null)
            ? null
            : gradeRecall(run.outputText, profile);
        runRows.add({
          'model_order': modelOrder,
          'run_number': runIndex + 1,
          'model_id': aggregate.modelId,
          'model_name': aggregate.modelName,
          'model_path': aggregate.modelPath,
          'engine_type': aggregate.engine.name,
          'prompt_format': aggregate.promptFormat.name,
          'ttft_seconds': run.ttftSeconds,
          'latency_seconds': run.totalLatencySeconds,
          'token_count': run.tokenCount,
          'output_text': run.outputText,
          'error_message': run.errorMessage,
          'recall_found': recall?.found,
          'recall_total': recall?.total,
          'missed_fact_ids': recall == null
              ? null
              : jsonEncode(recall.missedTokens),
        });
      }
    }

    final expectedRunCount = _aggregates.length * runsPerModel;
    if (runRows.length != expectedRunCount) {
      throw StateError(
        'Incomplete benchmark: expected $expectedRunCount run records, '
        'but found ${runRows.length}.',
      );
    }

    return DatabaseService.instance.insertCompletedBenchmark(
      passage: passage,
      instruction: instruction,
      runsPerModel: runsPerModel,
      modelCount: _aggregates.length,
      runs: runRows,
      qualificationArtifactId: widget.qualificationArtifactId,
    );
  }

  Future<BenchmarkModelResult> _executeSingleBenchmark(
    ModelInfo model,
    String fullPrompt,
  ) async {
    final Stopwatch totalStopwatch = Stopwatch();
    final Stopwatch ttftStopwatch = Stopwatch();

    double? timeToFirstToken;
    String output = '';
    int tokenCount = 0;

    try {
      // Release any previously resident engine to prevent multi-GB memory pileup
      await _modelManager.unloadAllEngines();

      // 1. GEMINI NANO
      if (model.engine == ModelEngine.nano) {
        totalStopwatch.start();
        final resultText = await GeminiNanoService.generateText(
          prompt: fullPrompt,
          temperature: 0.2,
          topK: 40,
          maxTokens: 256,
        );
        totalStopwatch.stop();

        final double totalSec = totalStopwatch.elapsedMilliseconds / 1000.0;
        final int estTokens = estimateOutputTokens(resultText);
        final double speed = totalSec > 0 ? (estTokens / totalSec) : 0;

        final res = BenchmarkModelResult(
          modelName: model.name,
          engine: model.engine,
          ttftSeconds: totalSec,
          totalLatencySeconds: totalSec,
          tokenCount: estTokens,
          tokensPerSecond: speed,
          outputText: resultText,
        );

        return res;
      }

      // 2. GGUF (llama.cpp)
      if (model.engine == ModelEngine.gguf) {
        await LlamaGgufService.loadModel(
          modelPath: model.path,
          threads: 4,
          contextSize: 2048,
        );

        final Completer<void> streamCompleter = Completer<void>();
        final stream = LlamaGgufService.generate(
          prompt: fullPrompt,
          temperature: 0.2,
          topK: 40,
          maxTokens: 256,
        );

        bool isFirstChunk = true;
        totalStopwatch.start();
        ttftStopwatch.start();

        final subscription = stream.listen(
          (chunk) {
            if (chunk.isNotEmpty) {
              if (isFirstChunk) {
                ttftStopwatch.stop();
                timeToFirstToken = ttftStopwatch.elapsedMilliseconds / 1000.0;
                isFirstChunk = false;
              }
              output += chunk;
            }
          },
          onError: (err) {
            if (!streamCompleter.isCompleted) {
              streamCompleter.completeError(err);
            }
          },
          onDone: () {
            if (!streamCompleter.isCompleted) streamCompleter.complete();
          },
          cancelOnError: true,
        );

        await streamCompleter.future;
        await subscription.cancel();
        totalStopwatch.stop();
        await LlamaGgufService.unloadModel();

        tokenCount = estimateOutputTokens(output);
        final double totalSec = totalStopwatch.elapsedMilliseconds / 1000.0;
        final double speed = totalSec > 0 ? (tokenCount / totalSec) : 0;

        final res = BenchmarkModelResult(
          modelName: model.name,
          engine: model.engine,
          ttftSeconds: timeToFirstToken,
          totalLatencySeconds: totalSec,
          tokenCount: tokenCount,
          tokensPerSecond: speed,
          outputText: output,
        );

        return res;
      }

      throw Exception('Unsupported engine type');
    } catch (e) {
      totalStopwatch.stop();
      ttftStopwatch.stop();
      await _modelManager.unloadAllEngines();

      return BenchmarkModelResult(
        modelName: model.name,
        engine: model.engine,
        ttftSeconds: null,
        totalLatencySeconds: totalStopwatch.elapsedMilliseconds / 1000.0,
        tokenCount: 0,
        tokensPerSecond: 0,
        outputText: '',
        errorMessage: e.toString(),
      );
    }
  }

  Widget _buildStatusBanner({required bool canRun, required bool isScanning}) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isUnavailable =
        !canRun && !isScanning && !_isRunning && !_isRestoring;
    final bool isComplete = _hasRestoredSession && !_isRunning;

    final Color backgroundColor = isUnavailable
        ? colors.errorContainer
        : isComplete
        ? colors.tertiaryContainer
        : colors.secondaryContainer;
    final Color foregroundColor = isUnavailable
        ? colors.onErrorContainer
        : isComplete
        ? colors.onTertiaryContainer
        : colors.onSecondaryContainer;

    final IconData icon = _isRunning
        ? Icons.hourglass_top_rounded
        : isUnavailable
        ? Icons.error_outline_rounded
        : isComplete
        ? Icons.check_circle_outline_rounded
        : Icons.info_outline_rounded;

    return Container(
      key: const Key('benchmark-status-banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foregroundColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _currentStatus,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestCaseCard() {
    final ThemeData theme = Theme.of(context);
    final bool disabled = _isRunning || _isRestoring;

    return Card(
      key: const Key('benchmark-test-case-card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Test case',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const Key('benchmark-edit-test-case'),
                  onPressed: disabled
                      ? null
                      : () => setState(
                          () => _isEditingTestCase = !_isEditingTestCase,
                        ),
                  icon: Icon(
                    _isEditingTestCase
                        ? Icons.check_rounded
                        : Icons.edit_outlined,
                  ),
                  label: Text(_isEditingTestCase ? 'Done' : 'Edit'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'INSTRUCTION',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 8),
            if (_isEditingTestCase)
              TextField(
                key: const Key('benchmark-instruction-field'),
                controller: _instructionController,
                minLines: 2,
                maxLines: 4,
                enabled: !disabled,
                decoration: const InputDecoration(
                  hintText: 'Enter the benchmark instruction',
                  border: OutlineInputBorder(),
                ),
              )
            else
              Text(
                _instructionController.text.trim().isEmpty
                    ? '(No instruction)'
                    : _instructionController.text.trim(),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            const SizedBox(height: 20),
            Text(
              'PASSAGE',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 8),
            if (_isEditingTestCase)
              TextField(
                key: const Key('benchmark-passage-field'),
                controller: _promptController,
                minLines: 4,
                maxLines: 8,
                enabled: !disabled,
                decoration: const InputDecoration(
                  hintText: 'Enter the passage to compare',
                  border: OutlineInputBorder(),
                ),
              )
            else
              Text(
                _promptController.text.trim().isEmpty
                    ? '(No passage)'
                    : _promptController.text.trim(),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
              ),
          ],
        ),
      ),
    );
  }

  String _engineLabel(ModelEngine engine) {
    return switch (engine) {
      ModelEngine.nano => 'AICore',
      ModelEngine.gguf => 'GGUF',
      ModelEngine.litertlm => 'LiteRT-LM',
      ModelEngine.mediapipe => 'Legacy',
    };
  }

  Widget _buildEngineBadge(ModelEngine engine) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _engineLabel(engine),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.onSecondaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildModelSelection({
    required List<ModelInfo> availableModels,
    required bool disabled,
  }) {
    final ThemeData theme = Theme.of(context);
    final int selectedCount = availableModels
        .where((ModelInfo model) => _selectedModelIds.contains(model.id))
        .length;
    final bool allSelected =
        availableModels.isNotEmpty && selectedCount == availableModels.length;

    return Card(
      key: const Key('benchmark-model-selection'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Models',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$selectedCount of ${availableModels.length} selected',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    key: const Key('benchmark-select-all-models'),
                    onPressed:
                        disabled || allSelected || availableModels.isEmpty
                        ? null
                        : () => _selectAllModels(availableModels),
                    child: const Text('Select all'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (availableModels.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'No benchmark-compatible models are installed.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final ModelInfo model in availableModels)
                CheckboxListTile(
                  key: Key('benchmark-model-${model.id}'),
                  value: _selectedModelIds.contains(model.id),
                  onChanged: disabled
                      ? null
                      : (bool? selected) =>
                            _setModelSelected(model.id, selected ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(
                    model.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(model.formattedSize),
                  secondary: _buildEngineBadge(model.engine),
                ),
            if (availableModels.length < 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Text(
                  'Install at least 2 models to run a comparison.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              )
            else if (selectedCount < 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Text(
                  'Select at least 2 models to run a comparison.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRunSelector() {
    final bool disabled = _isRunning || _isRestoring;

    return Column(
      key: const Key('benchmark-runs-per-model'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Runs per model',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment<int>(value: 1, label: Text('1 run')),
              ButtonSegment<int>(value: 3, label: Text('3 runs')),
              ButtonSegment<int>(value: 5, label: Text('5 runs')),
            ],
            selected: <int>{_runsPerModel},
            showSelectedIcon: false,
            onSelectionChanged: disabled
                ? null
                : (Set<int> selection) {
                    setState(() => _runsPerModel = selection.first);
                  },
          ),
        ),
      ],
    );
  }

  String _runButtonLabel(List<ModelInfo> models) {
    if (_isRestoring) return 'Restoring last benchmark…';
    if (_isRunning) {
      return 'Model ${_currentRunningIndex + 1}/${models.length} '
          '• Run $_currentRunNumber/$_runsPerModel';
    }
    if (widget.isCandidateQualification) {
      return 'Benchmark model × $_runsPerModel';
    }
    final String runs = _runsPerModel == 1 ? 'run' : 'runs';
    return 'Run ${models.length} models × $_runsPerModel $runs';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<ModelInfo> availableModels = benchmarkModelsForTarget(
      _modelManager.availableModels,
      targetModelId: widget.targetModelId,
    );
    final List<ModelInfo> models = benchmarkModelsForTarget(
      _modelManager.availableModels,
      targetModelId: widget.targetModelId,
      selectedModelIds: widget.isCandidateQualification
          ? null
          : _selectedModelIds,
    );
    final bool canRun = canRunBenchmarkModels(
      models,
      isCandidateQualification: widget.isCandidateQualification,
    );
    final bool isScanning = _modelManager.isLoading;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 82,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isCandidateQualification ? 'Model Benchmark' : 'Benchmark',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              widget.isCandidateQualification
                  ? 'Single-model on-device test'
                  : 'Controlled on-device comparison',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          if (widget.isCandidateQualification)
            IconButton(
              icon: const Icon(Icons.folder_open_outlined),
              tooltip: 'Saved sessions',
              onPressed: (_isRunning || _isRestoring)
                  ? null
                  : _openSavedSessions,
            )
          else
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Settings',
              onPressed: () => openSettings(context),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildStatusBanner(canRun: canRun, isScanning: isScanning),
            const SizedBox(height: 16),
            _buildTestCaseCard(),
            const SizedBox(height: 16),
            if (!widget.isCandidateQualification) ...[
              _buildModelSelection(
                availableModels: availableModels,
                disabled: isScanning || _isRunning || _isRestoring,
              ),
              const SizedBox(height: 20),
            ],
            _buildRunSelector(),
            const SizedBox(height: 16),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                key: const Key('benchmark-run-button'),
                onPressed: isScanning || _isRunning || _isRestoring || !canRun
                    ? null
                    : _runBenchmarkSuite,
                icon: _isRunning
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(
                  _runButtonLabel(models),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (_aggregates.isNotEmpty) ...[
              const SizedBox(height: 24),
              Card(
                key: const Key('benchmark-results-card'),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.isCandidateQualification
                                      ? 'Model result'
                                      : 'Comparison results',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  _hasRestoredSession
                                      ? 'Medians from the saved session'
                                      : 'Live benchmark progress',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!widget.isCandidateQualification)
                            TextButton(
                              onPressed: _isRunning || _isRestoring
                                  ? null
                                  : _openSavedSessions,
                              child: const Text('Saved sessions'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      BenchmarkResultsTable(
                        aggregates: _aggregates,
                        showAccuracy: false,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
