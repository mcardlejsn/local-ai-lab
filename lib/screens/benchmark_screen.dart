import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/benchmark_session.dart';
import '../models/recall_checklist.dart';
import '../services/database_service.dart';
import '../services/gemini_nano_service.dart';
import '../services/llama_gguf_service.dart';
import '../services/mediapipe_gemma_service.dart';
import '../services/model_manager_service.dart';
import '../widgets/benchmark_results_table.dart';
import 'saved_benchmark_sessions_screen.dart';

// The result classes moved to lib/models/benchmark_session.dart so the archive
// screens can share them. Re-exported here so existing imports of this file
// continue to resolve them.
export '../models/benchmark_session.dart'
    show BenchmarkModelResult, BenchmarkAggregate;

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  final ModelManagerService _modelManager = ModelManagerService();
  final TextEditingController _promptController = TextEditingController(
    text: defaultBenchmarkPassage,
  );
  final TextEditingController _instructionController = TextEditingController(
    text: defaultBenchmarkInstruction,
  );

  final List<BenchmarkAggregate> _aggregates = [];
  int _runsPerModel = 3;
  bool _isRunning = false;
  bool _isRestoring = true;
  bool _hasRestoredSession = false;
  int _currentRunningIndex = -1;
  int _currentRunNumber = 0;
  String _currentStatus = 'Ready to benchmark.';

  @override
  void initState() {
    super.initState();
    _modelManager.addListener(_onModelManagerStateChanged);
    // The picker's selection is derived from the passage text, so edits typed
    // straight into the field have to redraw it.
    _promptController.addListener(_onPassageTextChanged);
    _initializeScreen();
  }

  void _onPassageTextChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initializeScreen() async {
    try {
      await _restoreLatestBenchmark();
    } catch (e) {
      if (mounted) {
        setState(() {
          _currentStatus = 'Could not restore the latest benchmark: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRestoring = false;
        });
      }
    }

    if (mounted) {
      await _modelManager.scanModels();
    }
  }

  Future<void> _restoreLatestBenchmark() async {
    final saved = await DatabaseService.instance.getLatestCompletedBenchmark();
    if (saved == null || !mounted) return;

    final runMaps = (saved['runs'] as List).cast<Map<String, Object?>>();
    final restored = buildAggregatesFromSavedRuns(runMaps);
    final completedAt =
        DateTime.parse(saved['completed_at'] as String).toLocal();

    setState(() {
      _promptController.text = saved['passage'] as String;
      _instructionController.text = saved['instruction'] as String;
      _runsPerModel = saved['runs_per_model'] as int;
      _aggregates
        ..clear()
        ..addAll(restored);
      _hasRestoredSession = true;
      _currentStatus = 'Restored benchmark completed '
          '${formatBenchmarkDateTime(completedAt)}.';
    });
  }

  /// Re-reads the most recently saved session's runs into the displayed
  /// results, so the table shows the recall grades written at save time.
  Future<void> _reloadSavedRuns() async {
    final saved = await DatabaseService.instance.getLatestCompletedBenchmark();
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
      MaterialPageRoute(
        builder: (_) => const SavedBenchmarkSessionsScreen(),
      ),
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
        if (!_isRunning && !_isRestoring && !_hasRestoredSession) {
          final models = _modelManager.availableModels;
          _currentStatus = models.isEmpty
              ? 'No models found to benchmark.'
              : 'Found ${models.length} models ready for testing.';
        }
      });
    }
  }

  Future<void> _runBenchmarkSuite() async {
    final models = _modelManager.availableModels;
    if (models.isEmpty || _isRunning) return;

    setState(() {
      _isRunning = true;
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
        engine: model.engine,
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
      await _saveCompletedBenchmark(
        passage: rawText,
        instruction: instruction,
        runsPerModel: runsPerModel,
      );
      // Re-read what was just written so the displayed runs carry their
      // stored recall grades.
      await _reloadSavedRuns();
    } catch (e) {
      saveError = e.toString();
    }

    if (mounted) {
      setState(() {
        _isRunning = false;
        _hasRestoredSession = saveError == null;
        _currentRunningIndex = -1;
        _currentRunNumber = 0;
        _currentStatus = saveError == null
            ? 'Benchmark suite completed and saved: '
                '${_aggregates.length} models × $runsPerModel runs.'
            : 'Benchmark suite completed, but the grouped session '
                'could not be saved: $saveError';
      });
    }

    // Restore the model the user has selected. The suite leaves whichever model
    // ran last resident, so without this the summarizer would either find no
    // engine or, for MediaPipe, silently run on the last benchmarked model.
    // loadModel releases every engine before loading, so this also handles the
    // cleanup of whatever the suite left behind.
    final selectedModel = _modelManager.activeModel;
    if (selectedModel == null) {
      await _modelManager.unloadAllEngines();
    } else {
      await _modelManager.loadModel(selectedModel);
    }
  }

  Future<void> _saveCompletedBenchmark({
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
          'missed_fact_ids':
              recall == null ? null : jsonEncode(recall.missedTokens),
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

    await DatabaseService.instance.insertCompletedBenchmark(
      passage: passage,
      instruction: instruction,
      runsPerModel: runsPerModel,
      modelCount: _aggregates.length,
      runs: runRows,
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

      // 3. MEDIAPIPE (Gemma)
      if (model.engine == ModelEngine.mediapipe) {
        await MediaPipeGemmaService.install(model.path);
        await MediaPipeGemmaService.createSession(
          temperature: 0.2,
          topK: 40,
          randomSeed: 1,
        );

        final stream = await MediaPipeGemmaService.generate(fullPrompt);

        final Completer<void> streamCompleter = Completer<void>();
        bool isFirstChunk = true;
        totalStopwatch.start();
        ttftStopwatch.start();

        final subscription = stream.listen(
          (chunk) {
            if (isFirstChunk) {
              ttftStopwatch.stop();
              timeToFirstToken = ttftStopwatch.elapsedMilliseconds / 1000.0;
              isFirstChunk = false;
            }
            output += chunk;
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

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF121212);
    const surfaceColor = Color(0xFF1E1E1E);
    const accentBlue = Color(0xFF90CAF9);

    final models = _modelManager.availableModels;
    final isScanning = _modelManager.isLoading;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        elevation: 0,
        title: const Text(
          'Model Benchmark Suite',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_rounded, color: accentBlue),
            tooltip: 'Saved sessions',
            onPressed: (_isRunning || _isRestoring) ? null : _openSavedSessions,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Icon(
                    _isRunning
                        ? Icons.hourglass_top_rounded
                        : (models.isEmpty
                            ? Icons.error_outline_rounded
                            : Icons.check_circle_outline_rounded),
                    color: _isRunning ? accentBlue : const Color(0xFF81C784),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _currentStatus,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Benchmark Instruction:',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: TextField(
                controller: _instructionController,
                maxLines: 2,
                enabled: !_isRunning && !_isRestoring,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.all(10),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Passage:',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: TextField(
                controller: _promptController,
                maxLines: 4,
                enabled: !_isRunning && !_isRestoring,
                style: const TextStyle(
                    color: Colors.white, fontSize: 13, height: 1.4),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.all(10),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  'Runs per model:',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
                const SizedBox(width: 12),
                ...[1, 3, 5].map((n) {
                  final bool selected = _runsPerModel == n;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('$n'),
                      selected: selected,
                      onSelected: (_isRunning || _isRestoring)
                          ? null
                          : (value) {
                              if (value) setState(() => _runsPerModel = n);
                            },
                      backgroundColor: surfaceColor,
                      selectedColor: accentBlue,
                      side: const BorderSide(color: Colors.white24),
                      labelStyle: TextStyle(
                        color: selected ? Colors.black : Colors.white70,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      showCheckmark: false,
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed:
                  (isScanning || _isRunning || _isRestoring || models.isEmpty)
                      ? null
                      : _runBenchmarkSuite,
              icon: _isRunning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.play_arrow_rounded, color: Colors.black),
              label: Text(
                _isRestoring
                    ? 'Restoring Last Benchmark...'
                    : _isRunning
                        ? 'Model ${_currentRunningIndex + 1}/${models.length} '
                            '• Run $_currentRunNumber/$_runsPerModel'
                        : 'Run Automated Benchmark Suite',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentBlue,
                disabledBackgroundColor: Colors.white24,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 20),
            if (_aggregates.isNotEmpty) ...[
              const Text(
                'Comparative Results:',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15),
              ),
              const SizedBox(height: 8),
              BenchmarkResultsTable(
                aggregates: _aggregates,
                showAccuracy: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}