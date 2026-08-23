import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../models/summary_record.dart';
import '../services/database_service.dart';
import '../services/gemini_nano_service.dart';
import '../services/llama_gguf_service.dart';
import '../services/model_manager_service.dart';

class BenchmarkModelResult {
  final String modelName;
  final ModelEngine engine;
  final double? ttftSeconds;
  final double totalLatencySeconds;
  final int tokenCount;
  final double tokensPerSecond;
  final String outputText;
  final String? errorMessage;

  BenchmarkModelResult({
    required this.modelName,
    required this.engine,
    this.ttftSeconds,
    required this.totalLatencySeconds,
    required this.tokenCount,
    required this.tokensPerSecond,
    required this.outputText,
    this.errorMessage,
  });
}

class BenchmarkAggregate {
  final String modelId;
  final String modelName;
  final String modelPath;
  final ModelEngine engine;
  final PromptFormat promptFormat;
  final List<BenchmarkModelResult> runs = [];

  BenchmarkAggregate({
    required this.modelId,
    required this.modelName,
    required this.modelPath,
    required this.engine,
    required this.promptFormat,
  });

  List<BenchmarkModelResult> get successfulRuns =>
      runs.where((r) => r.errorMessage == null).toList();

  bool get hasAnySuccess => successfulRuns.isNotEmpty;

  String? get firstError {
    for (final r in runs) {
      if (r.errorMessage != null) return r.errorMessage;
    }
    return null;
  }

  static double? _median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final int mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  double? get medianTokensPerSecond =>
      _median(successfulRuns.map((r) => r.tokensPerSecond).toList());

  double? get medianTtftSeconds => _median(
        successfulRuns
            .where((r) => r.ttftSeconds != null)
            .map((r) => r.ttftSeconds!)
            .toList(),
      );

  double? get medianLatencySeconds =>
      _median(successfulRuns.map((r) => r.totalLatencySeconds).toList());

  double? get minLatencySeconds {
    final s = successfulRuns;
    if (s.isEmpty) return null;
    return s.map((r) => r.totalLatencySeconds).reduce((a, b) => a < b ? a : b);
  }

  double? get maxLatencySeconds {
    final s = successfulRuns;
    if (s.isEmpty) return null;
    return s.map((r) => r.totalLatencySeconds).reduce((a, b) => a > b ? a : b);
  }

  int? get medianTokenCount {
    final value =
        _median(successfulRuns.map((r) => r.tokenCount.toDouble()).toList());
    return value?.round();
  }

  /// The run whose total latency sits at the median, used as the representative
  /// output so the displayed text corresponds to the displayed timings.
  BenchmarkModelResult? get medianRun {
    final s = successfulRuns;
    if (s.isEmpty) return null;
    final sorted = [...s]
      ..sort((a, b) => a.totalLatencySeconds.compareTo(b.totalLatencySeconds));
    return sorted[(sorted.length - 1) ~/ 2];
  }
}

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  final ModelManagerService _modelManager = ModelManagerService();
  final TextEditingController _promptController = TextEditingController(
    text:
        'Client arrived at 08:30 for morning medication (Metformin 500mg, Lisinopril 10mg) with full glass of water. Refused breakfast initially citing mild nausea, but ate half a banana at 09:15. Blood glucose reading at 09:30 was 128 mg/dL. Attended physical therapy session from 10:00 to 10:45 with good mobility and no complaints of pain. Returned to common area for lunch at 12:00.',
  );
  final TextEditingController _instructionController = TextEditingController(
    text:
        'Extract all timestamps, vitals, and medication events chronologically:',
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
    _initializeScreen();
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
    final aggregatesByOrder = <int, BenchmarkAggregate>{};

    for (final runMap in runMaps) {
      final modelOrder = runMap['model_order'] as int;
      final aggregate = aggregatesByOrder.putIfAbsent(
        modelOrder,
        () => BenchmarkAggregate(
          modelId: runMap['model_id'] as String,
          modelName: runMap['model_name'] as String,
          modelPath: runMap['model_path'] as String,
          engine: ModelEngine.values.byName(
            runMap['engine_type'] as String,
          ),
          promptFormat: PromptFormat.values.byName(
            runMap['prompt_format'] as String,
          ),
        ),
      );

      final latencySeconds = (runMap['latency_seconds'] as num).toDouble();
      final tokenCount = runMap['token_count'] as int;
      aggregate.runs.add(
        BenchmarkModelResult(
          modelName: runMap['model_name'] as String,
          engine: aggregate.engine,
          ttftSeconds: (runMap['ttft_seconds'] as num?)?.toDouble(),
          totalLatencySeconds: latencySeconds,
          tokenCount: tokenCount,
          tokensPerSecond: latencySeconds > 0 ? tokenCount / latencySeconds : 0,
          outputText: runMap['output_text'] as String,
          errorMessage: runMap['error_message'] as String?,
        ),
      );
    }

    final orderedEntries = aggregatesByOrder.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final completedAt =
        DateTime.parse(saved['completed_at'] as String).toLocal();

    setState(() {
      _promptController.text = saved['passage'] as String;
      _instructionController.text = saved['instruction'] as String;
      _runsPerModel = saved['runs_per_model'] as int;
      _aggregates
        ..clear()
        ..addAll(orderedEntries.map((entry) => entry.value));
      _hasRestoredSession = true;
      _currentStatus =
          'Restored benchmark completed ${_formatDateTime(completedAt)}.';
    });
  }

  String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final year = value.year.toString();
    final minute = value.minute.toString().padLeft(2, '0');
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final period = value.hour < 12 ? 'AM' : 'PM';
    return '$month/$day/$year $hour12:$minute $period';
  }

  @override
  void dispose() {
    _modelManager.removeListener(_onModelManagerStateChanged);
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

        final result = await _executeSingleBenchmark(
            model, fullPrompt, rawText, instruction);

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
  }

  Future<void> _saveCompletedBenchmark({
    required String passage,
    required String instruction,
    required int runsPerModel,
  }) async {
    final runRows = <Map<String, Object?>>[];

    for (int modelOrder = 0; modelOrder < _aggregates.length; modelOrder++) {
      final aggregate = _aggregates[modelOrder];
      for (int runIndex = 0; runIndex < aggregate.runs.length; runIndex++) {
        final run = aggregate.runs[runIndex];
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
    String originalText,
    String taskType,
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

        await _saveResultToDb(originalText, resultText, taskType, res);
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

        await _saveResultToDb(originalText, output, taskType, res);
        return res;
      }

      // 3. MEDIAPIPE (Gemma)
      if (model.engine == ModelEngine.mediapipe) {
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
        ).fromFile(model.path).install();

        final gemmaModel = await FlutterGemma.getActiveModel();
        final session = await gemmaModel.createSession(
          temperature: 0.2,
          topK: 40,
          randomSeed: 1,
        );

        await session.addQueryChunk(Message(text: fullPrompt, isUser: true));
        final stream = session.getResponseAsync();

        final Completer<void> streamCompleter = Completer<void>();
        bool isFirstChunk = true;
        totalStopwatch.start();
        ttftStopwatch.start();

        final subscription = stream.listen(
          (dynamic chunk) {
            final String textChunk = chunk?.toString() ?? '';
            if (textChunk.isNotEmpty) {
              if (isFirstChunk) {
                ttftStopwatch.stop();
                timeToFirstToken = ttftStopwatch.elapsedMilliseconds / 1000.0;
                isFirstChunk = false;
              }
              output += textChunk;
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

        await _saveResultToDb(originalText, output, taskType, res);
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

  Future<void> _saveResultToDb(
    String originalText,
    String summary,
    String taskType,
    BenchmarkModelResult res,
  ) async {
    if (summary.trim().isEmpty) return;

    final record = SummaryRecord(
      originalText: originalText,
      generatedSummary: summary,
      taskType: 'Benchmark: $taskType',
      createdAt: DateTime.now(),
      latencySeconds: res.totalLatencySeconds,
      ttftSeconds: res.ttftSeconds,
      tokensPerSecond: res.tokensPerSecond,
      engineType: res.engine.name,
      modelName: res.modelName,
      tokenCount: res.tokenCount > 0 ? res.tokenCount : null,
    );

    await DatabaseService.instance.insertSummary(record);
  }

  void _showOutputModal(BenchmarkAggregate item) {
    final representative = item.medianRun;
    final String outputText = representative?.outputText ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (_, controller) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                controller: controller,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.modelName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded,
                            color: Color(0xFF90CAF9), size: 20),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: outputText));
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Copied output to clipboard.')),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 4),
                  const Text(
                    'Per-run latency:',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...List.generate(item.runs.length, (index) {
                    final run = item.runs[index];
                    final bool failed = run.errorMessage != null;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        failed
                            ? 'Run ${index + 1}: failed — ${run.errorMessage}'
                            : 'Run ${index + 1}: ${run.totalLatencySeconds.toStringAsFixed(2)}s'
                                ' · ${run.tokensPerSecond.toStringAsFixed(1)} est. tok/s'
                                ' · ${run.tokenCount} est. tokens',
                        style: TextStyle(
                          color: failed ? Colors.redAccent : Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  const Text(
                    'Output (median-latency run):',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    outputText.isEmpty ? '(No output generated)' : outputText,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14, height: 1.4),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
              'Standardized Passage (Shift Note):',
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
              Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(Colors.black26),
                    dataRowMinHeight: 48,
                    dataRowMaxHeight: 64,
                    columns: const [
                      DataColumn(
                        label: Text(
                          'Model / Engine',
                          style: TextStyle(
                              color: accentBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Runs',
                          style: TextStyle(
                              color: accentBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Est. tok/s (chars÷4)',
                          style: TextStyle(
                              color: accentBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'TTFT (s)',
                          style: TextStyle(
                              color: accentBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Latency (s)',
                          style: TextStyle(
                              color: accentBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Est. tokens',
                          style: TextStyle(
                              color: accentBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Output',
                          style: TextStyle(
                              color: accentBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    rows: _aggregates.map((agg) {
                      final bool hasResults = agg.hasAnySuccess;
                      final double? medianSpeed = agg.medianTokensPerSecond;
                      final double? medianTtft = agg.medianTtftSeconds;
                      final double? medianLatency = agg.medianLatencySeconds;
                      final double? minLatency = agg.minLatencySeconds;
                      final double? maxLatency = agg.maxLatencySeconds;
                      final int? medianTokens = agg.medianTokenCount;
                      final int successCount = agg.successfulRuns.length;

                      return DataRow(
                        cells: [
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                agg.modelName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '$successCount/${agg.runs.length}',
                              style: TextStyle(
                                color: successCount == agg.runs.length
                                    ? Colors.white70
                                    : Colors.orangeAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              medianSpeed != null
                                  ? medianSpeed.toStringAsFixed(1)
                                  : 'ERR',
                              style: TextStyle(
                                color: hasResults
                                    ? const Color(0xFF81C784)
                                    : Colors.redAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              agg.engine == ModelEngine.nano
                                  ? (medianLatency != null
                                      ? '${medianLatency.toStringAsFixed(2)}s*'
                                      : '--')
                                  : (medianTtft != null
                                      ? '${medianTtft.toStringAsFixed(2)}s'
                                      : '--'),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  medianLatency != null
                                      ? '${medianLatency.toStringAsFixed(2)}s'
                                      : '--',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                if (successCount > 1 &&
                                    minLatency != null &&
                                    maxLatency != null)
                                  Text(
                                    '${minLatency.toStringAsFixed(2)}–${maxLatency.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(
                              medianTokens?.toString() ?? '--',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          DataCell(
                            IconButton(
                              icon: const Icon(
                                Icons.visibility_rounded,
                                size: 18,
                                color: accentBlue,
                              ),
                              onPressed: agg.runs.isEmpty
                                  ? null
                                  : () => _showOutputModal(agg),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Timings are the median across the runs completed for each model; the '
                'smaller figure under latency is the min–max range across those runs.\n'
                'Token counts are estimated as output characters ÷ 4, not tokenizer '
                'output. Each engine uses a different tokenizer, and the rate uses '
                'total latency including prompt processing and TTFT. It is therefore '
                'an end-to-end throughput proxy, not pure decode speed.\n'
                '* Gemini Nano\'s Prompt API is non-streaming — time to first token '
                'cannot be measured, so total latency is shown in that column.',
                style:
                    TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
