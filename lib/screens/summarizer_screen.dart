import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

import '../models/summary_record.dart';
import '../services/database_service.dart';
import '../services/gemini_nano_service.dart';
import '../services/llama_gguf_service.dart';
import 'history_screen.dart';

enum ModelEngine { nano, mediapipe, gguf }

class ModelOption {
  final String id;
  final String displayName;
  final ModelEngine engine;
  final File? file;

  ModelOption({
    required this.id,
    required this.displayName,
    required this.engine,
    this.file,
  });
}

class SummarizerScreen extends StatefulWidget {
  const SummarizerScreen({super.key});

  @override
  State<SummarizerScreen> createState() => _SummarizerScreenState();
}

class _SummarizerScreenState extends State<SummarizerScreen> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _customPromptController = TextEditingController(
    text: 'Extract the 3 most critical points',
  );
  final ScrollController _scrollController = ScrollController();

  // Model & State Management
  List<ModelOption> _availableModels = [];
  String? _selectedModelId;
  bool _isModelInitialized = false;
  bool _isStreaming = false;
  String _statusMessage = 'Scanning for models...';
  String _generatedOutput = '';

  // Runtime Model Hyperparameters
  double _temperature = 0.20;
  int _topK = 40;
  int _maxTokens = 256;

  // Selected Preset Task
  String _selectedAction = '2-Sentence Summary';
  final Map<String, String> _presetPrompts = {
    '2-Sentence Summary':
        'Summarize the following passage in exactly two clear, concise sentences:',
    'Key Events':
        'Extract and list all significant events, milestones, and timestamps from the text in chronological order:',
    'Action Items':
        'Identify and list all actionable next steps, deliverables, and assignments from the text:',
    'Custom': '',
  };

  // Inference Benchmarking Metrics
  final Stopwatch _inferenceStopwatch = Stopwatch();
  final Stopwatch _ttftStopwatch = Stopwatch();
  double? _timeToFirstTokenSeconds;
  double? _totalLatencySeconds;
  int _estimatedTokenCount = 0;
  double? _tokensPerSecond;
  StreamSubscription<String?>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    _scanAndInitializeModels();
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    LlamaGgufService.unloadModel();
    _inputController.dispose();
    _customPromptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _scanAndInitializeModels() async {
    setState(() {
      _statusMessage = 'Scanning models...';
      _isModelInitialized = false;
    });

    try {
      final List<ModelOption> options = [];

      // 1. Check Gemini Nano AICore System Availability
      final bool isNanoReady = await GeminiNanoService.isAvailable();
      if (isNanoReady) {
        options.add(
          ModelOption(
            id: 'system_gemini_nano',
            displayName: 'Gemini Nano (AICore NPU)',
            engine: ModelEngine.nano,
          ),
        );
      }

      // 2. Scan sandbox storage for .bin, .task, and .gguf files
      final Directory? extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final List<Directory> searchDirs = [
          Directory('${extDir.path}/models'),
          extDir,
        ];

        for (final dir in searchDirs) {
          if (await dir.exists()) {
            try {
              final entities = dir.listSync(recursive: false);
              for (final entity in entities) {
                if (entity is File) {
                  final path = entity.path.toLowerCase();
                  if (path.endsWith('.bin') || path.endsWith('.task')) {
                    if (!options.any((o) => o.id == entity.path)) {
                      options.add(
                        ModelOption(
                          id: entity.path,
                          displayName: entity.path.split('/').last,
                          engine: ModelEngine.mediapipe,
                          file: entity,
                        ),
                      );
                    }
                  } else if (path.endsWith('.gguf')) {
                    if (!options.any((o) => o.id == entity.path)) {
                      options.add(
                        ModelOption(
                          id: entity.path,
                          displayName: entity.path.split('/').last,
                          engine: ModelEngine.gguf,
                          file: entity,
                        ),
                      );
                    }
                  }
                }
              }
            } catch (_) {}
          }
        }
      }

      setState(() {
        _availableModels = options;
      });

      if (options.isEmpty) {
        setState(() {
          _isModelInitialized = false;
          _selectedModelId = null;
          _statusMessage = 'No models found (Sandbox or System)';
        });
        return;
      }

      final String targetId = (_selectedModelId != null &&
              options.any((o) => o.id == _selectedModelId))
          ? _selectedModelId!
          : options.first.id;

      await _activateModel(targetId);
    } catch (e) {
      setState(() {
        _isModelInitialized = false;
        _statusMessage = 'Scan Error: $e';
      });
    }
  }

  Future<void> _activateModel(String modelId) async {
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    _stopTimers();

    final modelOption = _availableModels.firstWhere((o) => o.id == modelId);

    setState(() {
      _selectedModelId = modelId;
      _isModelInitialized = false;
      _isStreaming = false;
      _statusMessage = 'Initializing ${modelOption.displayName}...';
    });

    if (modelOption.engine != ModelEngine.gguf) {
      await LlamaGgufService.unloadModel();
    }

    if (modelOption.engine == ModelEngine.nano) {
      setState(() {
        _isModelInitialized = true;
        _statusMessage = 'Nano Ready (System NPU)';
      });
      return;
    }

    if (modelOption.engine == ModelEngine.mediapipe) {
      try {
        await FlutterGemma.installModel(
          modelType: ModelType.gemmaIt,
        ).fromFile(modelOption.id).install();

        setState(() {
          _isModelInitialized = true;
          _statusMessage = 'MediaPipe Ready (100% Offline)';
        });
      } catch (e) {
        setState(() {
          _isModelInitialized = false;
          _statusMessage = 'MediaPipe Load Error: $e';
        });
      }
      return;
    }

    if (modelOption.engine == ModelEngine.gguf) {
      try {
        await LlamaGgufService.loadModel(
          modelPath: modelOption.id,
          threads: 4,
          contextSize: 2048,
        );

        setState(() {
          _isModelInitialized = true;
          _statusMessage = 'GGUF Engine Ready (llama.cpp)';
        });
      } catch (e) {
        setState(() {
          _isModelInitialized = false;
          _statusMessage = 'GGUF Load Error: $e';
        });
      }
      return;
    }
  }

  void _resetMetrics() {
    _inferenceStopwatch.reset();
    _ttftStopwatch.reset();
    _timeToFirstTokenSeconds = null;
    _totalLatencySeconds = null;
    _estimatedTokenCount = 0;
    _tokensPerSecond = null;
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      setState(() {
        _inputController.text = data.text!;
      });
      _showSnackBar('Pasted from clipboard.');
    }
  }

  void _clearInput() {
    _inputController.clear();
    setState(() {
      _generatedOutput = '';
      _resetMetrics();
    });
  }

  Future<void> _runInference() async {
    final rawText = _inputController.text.trim();
    if (rawText.isEmpty) {
      _showSnackBar('Please enter or paste text to summarize.');
      return;
    }

    FocusScope.of(context).unfocus();
    _resetMetrics();

    String instruction = _presetPrompts[_selectedAction] ?? '';
    if (_selectedAction == 'Custom') {
      instruction = _customPromptController.text.trim();
      if (instruction.isEmpty) {
        instruction = 'Summarize the following passage:';
      }
    }

    final fullPrompt =
        '<start_of_turn>user\n$instruction\n\n"""\n$rawText\n"""<end_of_turn>\n<start_of_turn>model\n';

    setState(() {
      _isStreaming = true;
      _generatedOutput = '';
    });

    _inferenceStopwatch.start();
    _ttftStopwatch.start();

    final activeOption = _availableModels.firstWhere((o) => o.id == _selectedModelId);

    if (activeOption.engine == ModelEngine.nano) {
      try {
        final resultText = await GeminiNanoService.generateText(
          prompt: fullPrompt,
          temperature: _temperature,
          topK: _topK,
        );

        _stopTimers();

        final double totalSec = _inferenceStopwatch.elapsedMilliseconds / 1000.0;
        final int estTokens = (resultText.length / 4.0).ceil();

        setState(() {
          _isStreaming = false;
          _generatedOutput = resultText;
          _timeToFirstTokenSeconds = totalSec;
          _totalLatencySeconds = totalSec;
          _estimatedTokenCount = estTokens;
          _tokensPerSecond = totalSec > 0 ? (estTokens / totalSec) : 0;
        });

        _autoScroll();
      } catch (e) {
        _stopTimers();
        setState(() => _isStreaming = false);
        _showSnackBar('Nano Inference Failed: $e');
      }
      return;
    }

    if (activeOption.engine == ModelEngine.gguf) {
      try {
        final stream = LlamaGgufService.generate(
          prompt: fullPrompt,
          temperature: _temperature,
          topK: _topK,
          maxTokens: _maxTokens,
        );

        bool isFirstChunk = true;

        _streamSubscription = stream.listen(
          (chunk) {
            if (chunk.isNotEmpty) {
              if (isFirstChunk) {
                _ttftStopwatch.stop();
                _timeToFirstTokenSeconds =
                    _ttftStopwatch.elapsedMilliseconds / 1000.0;
                isFirstChunk = false;
              }

              final int tokenIncrement = (chunk.length / 4.0).ceil();
              final int increment = tokenIncrement > 0 ? tokenIncrement : 1;

              setState(() {
                _generatedOutput += chunk;
                _estimatedTokenCount += increment;

                final double currentElapsedSec =
                    _inferenceStopwatch.elapsedMilliseconds / 1000.0;
                if (currentElapsedSec > 0) {
                  _tokensPerSecond = _estimatedTokenCount / currentElapsedSec;
                }
              });

              _autoScroll();
            }
          },
          onError: (error) {
            _stopTimers();
            setState(() => _isStreaming = false);
            _showSnackBar('GGUF Stream Error: $error');
          },
          onDone: () {
            _stopTimers();
            setState(() {
              _isStreaming = false;
              _totalLatencySeconds =
                  _inferenceStopwatch.elapsedMilliseconds / 1000.0;
              if (_totalLatencySeconds! > 0) {
                _tokensPerSecond = _estimatedTokenCount / _totalLatencySeconds!;
              }
            });
          },
          cancelOnError: true,
        );
      } catch (e) {
        _stopTimers();
        setState(() => _isStreaming = false);
        _showSnackBar('GGUF Inference Failed: $e');
      }
      return;
    }

    try {
      final model = await FlutterGemma.getActiveModel();
      final session = await model.createSession(
        temperature: _temperature,
        topK: _topK,
        randomSeed: 1,
      );

      await session.addQueryChunk(Message(text: fullPrompt, isUser: true));
      final stream = session.getResponseAsync();

      bool isFirstChunk = true;

      _streamSubscription = stream.listen(
        (chunk) {
          if (chunk.isNotEmpty) {
            if (isFirstChunk) {
              _ttftStopwatch.stop();
              _timeToFirstTokenSeconds =
                  _ttftStopwatch.elapsedMilliseconds / 1000.0;
              isFirstChunk = false;
            }

            final int tokenIncrement = (chunk.length / 4.0).ceil();
            final int increment = tokenIncrement > 0 ? tokenIncrement : 1;

            setState(() {
              _generatedOutput += chunk;
              _estimatedTokenCount += increment;

              final double currentElapsedSec =
                  _inferenceStopwatch.elapsedMilliseconds / 1000.0;
              if (currentElapsedSec > 0) {
                _tokensPerSecond = _estimatedTokenCount / currentElapsedSec;
              }
            });

            _autoScroll();
          }
        },
        onError: (error) {
          _stopTimers();
          setState(() => _isStreaming = false);
          _showSnackBar('Inference Stream Error: $error');
        },
        onDone: () {
          _stopTimers();
          setState(() {
            _isStreaming = false;
            _totalLatencySeconds =
                _inferenceStopwatch.elapsedMilliseconds / 1000.0;
            if (_totalLatencySeconds! > 0) {
              _tokensPerSecond = _estimatedTokenCount / _totalLatencySeconds!;
            }
          });
        },
        cancelOnError: true,
      );
    } catch (e) {
      _stopTimers();
      setState(() => _isStreaming = false);
      _showSnackBar('Inference Failed: $e');
    }
  }

  void _stopTimers() {
    if (_inferenceStopwatch.isRunning) _inferenceStopwatch.stop();
    if (_ttftStopwatch.isRunning) _ttftStopwatch.stop();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _saveCurrentSummary() async {
    if (_generatedOutput.trim().isEmpty) {
      _showSnackBar('No generated summary available to save.');
      return;
    }

    final record = SummaryRecord(
      originalText: _inputController.text.trim(),
      generatedSummary: _generatedOutput.trim(),
      taskType: _selectedAction,
      createdAt: DateTime.now(),
      latencySeconds: _totalLatencySeconds,
      ttftSeconds: _timeToFirstTokenSeconds,
      tokensPerSecond: _tokensPerSecond,
    );

    await DatabaseService.instance.insertSummary(record);
    _showSnackBar('Summary and telemetry saved to history.');
  }

  void _showSnackBar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E1E1E),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF121212);
    const surfaceColor = Color(0xFF1E1E1E);
    const accentBlue = Color(0xFF90CAF9);
    const successGreen = Color(0xFF81C784);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        elevation: 0,
        title: const Text(
          'Local AI Summarizer',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.content_paste_rounded, color: Colors.white70),
            tooltip: 'Paste from Clipboard',
            onPressed: _isStreaming ? null : _pasteFromClipboard,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            tooltip: 'Clear Input',
            onPressed: _isStreaming ? null : _clearInput,
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded, color: accentBlue),
            tooltip: 'Saved Summaries',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          children: [
            _buildModelSelectorCard(surfaceColor, accentBlue, successGreen),
            const SizedBox(height: 16),
            const Text(
              'Input Note / Passage:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: TextField(
                controller: _inputController,
                maxLines: 6,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                decoration: const InputDecoration(
                  hintText: 'Enter or paste passage here...',
                  hintStyle: TextStyle(color: Colors.white38),
                  contentPadding: EdgeInsets.all(12),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Runtime Model Controls',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          'T: ${_temperature.toStringAsFixed(2)} | K: $_topK | Max: $_maxTokens',
                          style: const TextStyle(
                            color: accentBlue,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Temperature', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text(
                        _temperature.toStringAsFixed(2),
                        style: const TextStyle(color: accentBlue, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: accentBlue,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: accentBlue,
                    ),
                    child: Slider(
                      value: _temperature,
                      min: 0.0,
                      max: 1.0,
                      divisions: 20,
                      onChanged: _isStreaming ? null : (v) => setState(() => _temperature = v),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Top-K Sampling', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text(
                        '$_topK',
                        style: const TextStyle(color: accentBlue, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: accentBlue,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: accentBlue,
                    ),
                    child: Slider(
                      value: _topK.toDouble(),
                      min: 1,
                      max: 40,
                      divisions: 39,
                      onChanged: _isStreaming ? null : (v) => setState(() => _topK = v.round()),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Max Output Tokens', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      Text(
                        '$_maxTokens',
                        style: const TextStyle(color: accentBlue, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: accentBlue,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: accentBlue,
                    ),
                    child: Slider(
                      value: _maxTokens.toDouble(),
                      min: 64,
                      max: 1024,
                      divisions: 15,
                      onChanged: _isStreaming ? null : (v) => setState(() => _maxTokens = v.round()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Custom Preset Instruction:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: TextField(
                      controller: _customPromptController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'e.g., Extract the 3 most critical points',
                        hintStyle: TextStyle(color: Colors.white38),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select AI Action:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presetPrompts.keys.map((action) {
                final isSelected = _selectedAction == action;
                return ChoiceChip(
                  label: Text(action),
                  selected: isSelected,
                  selectedColor: accentBlue.withValues(alpha: 0.3),
                  backgroundColor: surfaceColor,
                  labelStyle: TextStyle(
                    color: isSelected ? accentBlue : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                  side: BorderSide(
                    color: isSelected ? accentBlue : Colors.white24,
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedAction = action);
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: (!_isModelInitialized || _isStreaming) ? null : _runInference,
              icon: _isStreaming
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.bolt_rounded, color: Colors.black),
              label: Text(
                _isStreaming ? 'Generating...' : 'Summarize On-Device',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentBlue,
                disabledBackgroundColor: Colors.white24,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 14),
            _buildBenchmarkTelemetryBar(surfaceColor, accentBlue),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'OUTPUT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                          color: Colors.white70,
                        ),
                      ),
                      if (_generatedOutput.isNotEmpty)
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, size: 18, color: accentBlue),
                              tooltip: 'Copy Output',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _generatedOutput));
                                _showSnackBar('Copied to clipboard.');
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.bookmark_add_rounded, size: 18, color: accentBlue),
                              tooltip: 'Save Summary',
                              onPressed: _saveCurrentSummary,
                            ),
                          ],
                        ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 6),
                  SelectableText(
                    _generatedOutput.isEmpty
                        ? (_isStreaming ? 'Generating initial tokens...' : 'No summary generated yet.')
                        : _generatedOutput,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: _generatedOutput.isEmpty ? Colors.white38 : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildModelSelectorCard(Color surfaceColor, Color accentBlue, Color successGreen) {
    if (_availableModels.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.redAccent, width: 1.2),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _statusMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
              tooltip: 'Rescan Sandbox',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: _scanAndInitializeModels,
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isModelInitialized ? successGreen : accentBlue,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isModelInitialized ? Icons.bolt_rounded : Icons.sync_rounded,
                color: _isModelInitialized ? successGreen : accentBlue,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedModelId,
                    isExpanded: true,
                    dropdownColor: surfaceColor,
                    icon: Icon(Icons.arrow_drop_down_rounded, color: accentBlue),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    items: _availableModels.map((opt) {
                      return DropdownMenuItem<String>(
                        value: opt.id,
                        child: Text(opt.displayName, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: _isStreaming
                        ? null
                        : (newId) {
                            if (newId != null && newId != _selectedModelId) {
                              _activateModel(newId);
                            }
                          },
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                tooltip: 'Rescan Models',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _isStreaming ? null : _scanAndInitializeModels,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _statusMessage,
            style: TextStyle(
              color: _isModelInitialized ? successGreen : Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildBenchmarkTelemetryBar(Color surfaceColor, Color accentBlue) {
    final latencyText = _totalLatencySeconds != null
        ? '${_totalLatencySeconds!.toStringAsFixed(2)}s'
        : (_isStreaming
            ? '${(_inferenceStopwatch.elapsedMilliseconds / 1000.0).toStringAsFixed(1)}s'
            : '--');

    final ttftText = _timeToFirstTokenSeconds != null
        ? '${_timeToFirstTokenSeconds!.toStringAsFixed(2)}s'
        : '--';

    final speedText =
        _tokensPerSecond != null ? '${_tokensPerSecond!.toStringAsFixed(1)} tok/s' : '--';

    final tokensText = _estimatedTokenCount > 0 ? '$_estimatedTokenCount' : '--';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMetricColumn('LATENCY', latencyText),
          _buildVerticalDivider(),
          _buildMetricColumn('TTFT', ttftText),
          _buildVerticalDivider(),
          _buildMetricColumn('SPEED', speedText),
          _buildVerticalDivider(),
          _buildMetricColumn('TOKENS', tokensText),
        ],
      ),
    );
  }

  Widget _buildMetricColumn(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
            color: Colors.white38,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: value == '--' ? Colors.white24 : Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 22,
      width: 1,
      color: Colors.white12,
    );
  }
}