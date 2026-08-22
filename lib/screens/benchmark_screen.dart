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
    text: 'Extract all timestamps, vitals, and medication events chronologically:',
  );

  final List<BenchmarkModelResult> _results = [];
  bool _isRunning = false;
  int _currentRunningIndex = -1;
  String _currentStatus = 'Ready to benchmark.';

  @override
  void initState() {
    super.initState();
    _modelManager.addListener(_onModelManagerStateChanged);
    _modelManager.scanModels();
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
        if (!_isRunning) {
          final models = _modelManager.availableModels;
          _currentStatus = models.isEmpty
              ? 'No models found to benchmark.'
              : 'Found ${models.length} models ready for testing.';
        }
      });
    }
  }

  String _buildFormattedPrompt(ModelEngine engine, String instruction, String rawText) {
    if (engine == ModelEngine.nano) {
      return '$instruction\n\n"""\n$rawText\n"""';
    }
    return '<start_of_turn>user\n$instruction\n\n"""\n$rawText\n"""<end_of_turn>\n<start_of_turn>model\n';
  }

  Future<void> _runBenchmarkSuite() async {
    final models = _modelManager.availableModels;
    if (models.isEmpty || _isRunning) return;

    setState(() {
      _isRunning = true;
      _results.clear();
    });

    final String rawText = _promptController.text.trim();
    final String instruction = _instructionController.text.trim();

    for (int i = 0; i < models.length; i++) {
      if (!mounted) return;

      final model = models[i];

      setState(() {
        _currentRunningIndex = i;
        _currentStatus =
            'Benchmarking (${i + 1}/${models.length}): ${model.name}...';
      });

      await Future.delayed(const Duration(milliseconds: 250));

      final fullPrompt = _buildFormattedPrompt(model.engine, instruction, rawText);
      final result = await _executeSingleBenchmark(model, fullPrompt, rawText, instruction);

      if (mounted) {
        setState(() {
          _results.add(result);
        });
      }
    }

    if (mounted) {
      setState(() {
        _isRunning = false;
        _currentRunningIndex = -1;
        _currentStatus = 'Benchmark suite completed across ${_results.length} models.';
      });
    }
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
        final int estTokens = (resultText.length / 4.0).ceil();
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
              final int inc = (chunk.length / 4.0).ceil();
              tokenCount += (inc > 0 ? inc : 1);
            }
          },
          onError: (err) {
            if (!streamCompleter.isCompleted) streamCompleter.completeError(err);
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
              final int inc = (textChunk.length / 4.0).ceil();
              tokenCount += (inc > 0 ? inc : 1);
            }
          },
          onError: (err) {
            if (!streamCompleter.isCompleted) streamCompleter.completeError(err);
          },
          onDone: () {
            if (!streamCompleter.isCompleted) streamCompleter.complete();
          },
          cancelOnError: true,
        );

        await streamCompleter.future;
        await subscription.cancel();
        totalStopwatch.stop();

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
      generatedSummary: '[${res.modelName}]\n$summary',
      taskType: 'Benchmark: $taskType',
      createdAt: DateTime.now(),
      latencySeconds: res.totalLatencySeconds,
      ttftSeconds: res.ttftSeconds,
      tokensPerSecond: res.tokensPerSecond,
    );

    await DatabaseService.instance.insertSummary(record);
  }

  void _showOutputModal(BenchmarkModelResult item) {
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
                        icon: const Icon(Icons.copy_rounded, color: Color(0xFF90CAF9), size: 20),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: item.outputText));
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied output to clipboard.')),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 8),
                  SelectableText(
                    item.outputText.isEmpty ? '(No output generated)' : item.outputText,
                    style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
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
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                  if (!_isRunning)
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                      tooltip: 'Rescan',
                      onPressed: _modelManager.scanModels,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Benchmark Instruction:',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
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
                enabled: !_isRunning,
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
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
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
                enabled: !_isRunning,
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.all(10),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: (isScanning || _isRunning || models.isEmpty)
                  ? null
                  : _runBenchmarkSuite,
              icon: _isRunning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.play_arrow_rounded, color: Colors.black),
              label: Text(
                _isRunning
                    ? 'Running Suite (${_currentRunningIndex + 1}/${models.length})...'
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 20),
            if (_results.isNotEmpty) ...[
              const Text(
                'Comparative Results:',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
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
                    columns: const [
                      DataColumn(
                        label: Text(
                          'Model / Engine',
                          style: TextStyle(color: accentBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Speed (tok/s)',
                          style: TextStyle(color: accentBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'TTFT (s)',
                          style: TextStyle(color: accentBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Latency (s)',
                          style: TextStyle(color: accentBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Tokens',
                          style: TextStyle(color: accentBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Output',
                          style: TextStyle(color: accentBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    rows: _results.map((r) {
                      final bool isError = r.errorMessage != null;
                      return DataRow(
                        cells: [
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                r.modelName,
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
                              isError ? 'ERR' : r.tokensPerSecond.toStringAsFixed(1),
                              style: TextStyle(
                                color: isError ? Colors.redAccent : const Color(0xFF81C784),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              r.engine == ModelEngine.nano
                                  ? '${r.totalLatencySeconds.toStringAsFixed(2)}s*'
                                  : (r.ttftSeconds != null
                                      ? '${r.ttftSeconds!.toStringAsFixed(2)}s'
                                      : '--'),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${r.totalLatencySeconds.toStringAsFixed(2)}s',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          DataCell(
                            Text(
                              r.tokenCount.toString(),
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
                              onPressed: isError ? null : () => _showOutputModal(r),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
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