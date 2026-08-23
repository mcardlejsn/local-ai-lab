import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../models/summary_record.dart';
import '../services/database_service.dart';
import '../services/gemini_nano_service.dart';
import '../services/llama_gguf_service.dart';
import '../services/model_manager_service.dart';
import 'benchmark_screen.dart';
import 'history_screen.dart';

class SummarizerScreen extends StatefulWidget {
  const SummarizerScreen({super.key});

  @override
  State<SummarizerScreen> createState() => _SummarizerScreenState();
}

class _SummarizerScreenState extends State<SummarizerScreen> {
  static const String _samplePassage =
      "At Tuesday's 10:00 AM project meeting, Maya agreed to complete "
      'the accessibility review by Friday, and Daniel agreed to update the '
      'Android build. The current build passed its automated tests, but the '
      'settings screen still needs a small layout correction. The team will '
      'meet again Monday at 9:30 AM to review the release candidate.';

  final ModelManagerService _modelManager = ModelManagerService();
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _customPromptController = TextEditingController(
    text: 'Extract the 3 most critical points',
  );
  final ScrollController _scrollController = ScrollController();

  // Inference State
  bool _isStreaming = false;
  String _generatedOutput = '';

  // Hyperparameters
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

  // Inference Telemetry Metrics
  final Stopwatch _inferenceStopwatch = Stopwatch();
  final Stopwatch _ttftStopwatch = Stopwatch();
  double? _timeToFirstTokenSeconds;
  double? _totalLatencySeconds;
  int _estimatedTokenCount = 0;
  double? _tokensPerSecond;
  StreamSubscription<dynamic>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    _modelManager.addListener(_onModelManagerStateChanged);
    _modelManager.scanModels();
  }

  @override
  void dispose() {
    _modelManager.removeListener(_onModelManagerStateChanged);
    _streamSubscription?.cancel();
    _inputController.dispose();
    _customPromptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onModelManagerStateChanged() {
    if (mounted) setState(() {});
  }

  void _resetMetrics() {
    _inferenceStopwatch.reset();
    _ttftStopwatch.reset();
    _timeToFirstTokenSeconds = null;
    _totalLatencySeconds = null;
    _estimatedTokenCount = 0;
    _tokensPerSecond = null;
  }

  void _stopTimers() {
    if (_inferenceStopwatch.isRunning) _inferenceStopwatch.stop();
    if (_ttftStopwatch.isRunning) _ttftStopwatch.stop();
  }

  Future<void> _stopGeneration() async {
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    await LlamaGgufService.stop();
    _stopTimers();

    if (mounted) {
      setState(() {
        _isStreaming = false;
        _totalLatencySeconds = _inferenceStopwatch.elapsedMilliseconds / 1000.0;
        _estimatedTokenCount = estimateOutputTokens(_generatedOutput);
        if (_totalLatencySeconds != null && _totalLatencySeconds! > 0) {
          _tokensPerSecond = _estimatedTokenCount / _totalLatencySeconds!;
        }
      });
      _showSnackBar('Generation stopped by user.');
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null) {
        setState(() {
          _inputController.text = data.text!;
        });
        _showSnackBar('Pasted from clipboard.');
      }
    } catch (e) {
      _showSnackBar('Failed to read clipboard: $e');
    }
  }

  void _loadSamplePassage() {
    if (_isStreaming) return;

    setState(() {
      _inputController.text = _samplePassage;
      _inputController.selection = TextSelection.collapsed(
        offset: _inputController.text.length,
      );
      _generatedOutput = '';
      _resetMetrics();
    });
    _showSnackBar('Sample passage loaded.');
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

    final activeModel = _modelManager.activeModel;
    if (activeModel == null || _modelManager.isLoading) {
      _showSnackBar('No active model loaded.');
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

    final fullPrompt = buildInferencePrompt(
      engine: activeModel.engine,
      format: activeModel.promptFormat,
      instruction: instruction,
      rawText: rawText,
    );

    setState(() {
      _isStreaming = true;
      _generatedOutput = '';
    });

    _inferenceStopwatch.start();
    _ttftStopwatch.start();

    // 1. Gemini Nano Engine (AICore NPU)
    if (activeModel.engine == ModelEngine.nano) {
      try {
        final resultText = await GeminiNanoService.generateText(
          prompt: fullPrompt,
          temperature: _temperature,
          topK: _topK,
        );

        _stopTimers();
        final double totalSec =
            _inferenceStopwatch.elapsedMilliseconds / 1000.0;
        final int estTokens = estimateOutputTokens(resultText);

        if (mounted) {
          setState(() {
            _isStreaming = false;
            _generatedOutput = resultText;
            _timeToFirstTokenSeconds = totalSec;
            _totalLatencySeconds = totalSec;
            _estimatedTokenCount = estTokens;
            _tokensPerSecond = totalSec > 0 ? (estTokens / totalSec) : 0;
          });
          _autoScroll();
        }
      } catch (e) {
        _stopTimers();
        if (mounted) {
          setState(() => _isStreaming = false);
          _showSnackBar('Nano Inference Failed: $e');
        }
      }
      return;
    }

    // 2. GGUF Engine (llama.cpp)
    if (activeModel.engine == ModelEngine.gguf) {
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

              if (mounted) {
                setState(() {
                  _generatedOutput += chunk;
                  _estimatedTokenCount = estimateOutputTokens(_generatedOutput);

                  final double currentSec =
                      _inferenceStopwatch.elapsedMilliseconds / 1000.0;
                  if (currentSec > 0) {
                    _tokensPerSecond = _estimatedTokenCount / currentSec;
                  }
                });
                _autoScroll();
              }
            }
          },
          onError: (error) {
            _stopTimers();
            if (mounted) {
              setState(() => _isStreaming = false);
              _showSnackBar('GGUF Stream Error: $error');
            }
          },
          onDone: () {
            _stopTimers();
            if (mounted) {
              setState(() {
                _isStreaming = false;
                _totalLatencySeconds =
                    _inferenceStopwatch.elapsedMilliseconds / 1000.0;
                if (_totalLatencySeconds! > 0) {
                  _tokensPerSecond =
                      _estimatedTokenCount / _totalLatencySeconds!;
                }
              });
            }
          },
          cancelOnError: true,
        );
      } catch (e) {
        _stopTimers();
        if (mounted) {
          setState(() => _isStreaming = false);
          _showSnackBar('GGUF Inference Failed: $e');
        }
      }
      return;
    }

    // 3. MediaPipe Engine (Gemma .task / .bin)
    if (activeModel.engine == ModelEngine.mediapipe) {
      try {
        await _modelManager.recreateMediaPipeSession(
          temperature: _temperature,
          topK: _topK,
        );

        final dynamic session = _modelManager.activeMediaPipeSession;
        if (session == null) {
          throw Exception('MediaPipe session is not initialized.');
        }

        await session.addQueryChunk(Message(text: fullPrompt, isUser: true));
        final stream = session.getResponseAsync();

        bool isFirstChunk = true;

        _streamSubscription = stream.listen(
          (dynamic chunk) {
            final String textChunk = chunk?.toString() ?? '';
            if (textChunk.isNotEmpty) {
              if (isFirstChunk) {
                _ttftStopwatch.stop();
                _timeToFirstTokenSeconds =
                    _ttftStopwatch.elapsedMilliseconds / 1000.0;
                isFirstChunk = false;
              }

              if (mounted) {
                setState(() {
                  _generatedOutput += textChunk;
                  _estimatedTokenCount = estimateOutputTokens(_generatedOutput);

                  final double currentSec =
                      _inferenceStopwatch.elapsedMilliseconds / 1000.0;
                  if (currentSec > 0) {
                    _tokensPerSecond = _estimatedTokenCount / currentSec;
                  }
                });
                _autoScroll();
              }
            }
          },
          onError: (error) {
            _stopTimers();
            if (mounted) {
              setState(() => _isStreaming = false);
              _showSnackBar('MediaPipe Stream Error: $error');
            }
          },
          onDone: () {
            _stopTimers();
            if (mounted) {
              setState(() {
                _isStreaming = false;
                _totalLatencySeconds =
                    _inferenceStopwatch.elapsedMilliseconds / 1000.0;
                if (_totalLatencySeconds! > 0) {
                  _tokensPerSecond =
                      _estimatedTokenCount / _totalLatencySeconds!;
                }
              });
            }
          },
          cancelOnError: true,
        );
      } catch (e) {
        _stopTimers();
        if (mounted) {
          setState(() => _isStreaming = false);
          _showSnackBar('MediaPipe Inference Failed: $e');
        }
      }
    }
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 80),
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

    final activeModel = _modelManager.activeModel;

    final record = SummaryRecord(
      originalText: _inputController.text.trim(),
      generatedSummary: _generatedOutput.trim(),
      taskType: _selectedAction,
      createdAt: DateTime.now(),
      latencySeconds: _totalLatencySeconds,
      ttftSeconds: _timeToFirstTokenSeconds,
      tokensPerSecond: _tokensPerSecond,
      engineType: activeModel?.engine.name ?? 'unknown',
      modelName: activeModel?.name ?? 'Unknown Model',
      tokenCount: _estimatedTokenCount > 0 ? _estimatedTokenCount : null,
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

    final activeModel = _modelManager.activeModel;
    final isReady = activeModel != null && !_modelManager.isLoading;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        elevation: 0,
        title: const Text(
          'Local AI Lab',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.speed_rounded, color: accentBlue),
            tooltip: 'Run Benchmark Suite',
            onPressed: _isStreaming
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const BenchmarkScreen()),
                    );
                  },
          ),
          IconButton(
            icon:
                const Icon(Icons.content_paste_rounded, color: Colors.white70),
            tooltip: 'Paste from Clipboard',
            onPressed: _isStreaming ? null : _pasteFromClipboard,
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
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Input Note / Passage:',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _inputController,
                  builder: (_, value, __) {
                    if (value.text.isNotEmpty) {
                      return const SizedBox.shrink();
                    }
                    return TextButton.icon(
                      onPressed: _isStreaming ? null : _loadSamplePassage,
                      icon: const Icon(Icons.article_outlined, size: 16),
                      label: const Text('Load Sample'),
                      style: TextButton.styleFrom(
                        foregroundColor: accentBlue,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
              ],
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
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, height: 1.4),
                decoration: InputDecoration(
                  hintText: 'Enter or paste passage here...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  contentPadding: const EdgeInsets.all(12),
                  border: InputBorder.none,
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _inputController,
                    builder: (_, value, __) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(Icons.close_rounded,
                            size: 18, color: Colors.white38),
                        tooltip: 'Clear Input',
                        onPressed: _isStreaming ? null : _clearInput,
                      );
                    },
                  ),
                ),
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
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
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
            if (_selectedAction == 'Custom') ...[
              const SizedBox(height: 10),
              _buildCustomInstructionField(surfaceColor, accentBlue),
            ],
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: !isReady
                  ? null
                  : (_isStreaming ? _stopGeneration : _runInference),
              icon: _isStreaming
                  ? const Icon(Icons.stop_circle_rounded, color: Colors.white)
                  : const Icon(Icons.bolt_rounded, color: Colors.black),
              label: Text(
                _isStreaming ? 'Stop Generation' : 'Summarize On-Device',
                style: TextStyle(
                  color: _isStreaming ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isStreaming ? Colors.redAccent.shade700 : accentBlue,
                disabledBackgroundColor: Colors.white24,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 14),
            _buildBenchmarkTelemetryBar(surfaceColor, accentBlue),
            const SizedBox(height: 14),
            _buildOutputCard(surfaceColor, accentBlue),
            const SizedBox(height: 16),
            _buildControlsCard(surfaceColor, bgColor, accentBlue),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildModelSelectorCard(
      Color surfaceColor, Color accentBlue, Color successGreen) {
    final available = _modelManager.availableModels;
    final active = _modelManager.activeModel;
    final isLoading = _modelManager.isLoading;
    final status = _modelManager.statusMessage ?? 'Ready';

    if (available.isEmpty && !isLoading) {
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
            const Icon(Icons.error_outline_rounded,
                color: Colors.redAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                status,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: Colors.white70, size: 20),
              tooltip: 'Rescan Directory',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: _modelManager.scanModels,
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
          color: active != null && !isLoading ? successGreen : accentBlue,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLoading
                    ? Icons.sync_rounded
                    : (active != null
                        ? Icons.bolt_rounded
                        : Icons.info_outline_rounded),
                color: active != null && !isLoading ? successGreen : accentBlue,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: active?.id,
                    isExpanded: true,
                    dropdownColor: surfaceColor,
                    icon:
                        Icon(Icons.arrow_drop_down_rounded, color: accentBlue),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    items: available.map((m) {
                      return DropdownMenuItem<String>(
                        value: m.id,
                        child: Text('${m.name} (${m.formattedSize})',
                            overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (_isStreaming || isLoading)
                        ? null
                        : (newId) {
                            if (newId != null && newId != active?.id) {
                              final target =
                                  available.firstWhere((m) => m.id == newId);
                              _modelManager.loadModel(target);
                            }
                          },
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white70, size: 20),
                tooltip: 'Rescan Models',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: (_isStreaming || isLoading)
                    ? null
                    : _modelManager.scanModels,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            status,
            style: TextStyle(
              color:
                  active != null && !isLoading ? successGreen : Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildControlsCard(
      Color surfaceColor, Color bgColor, Color accentBlue) {
    return Material(
      color: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.white12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: accentBlue,
          collapsedIconColor: Colors.white54,
          title: Row(
            children: [
              const Flexible(
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
                  style: TextStyle(
                    color: accentBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Temperature',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                Text(
                  _temperature.toStringAsFixed(2),
                  style:
                      TextStyle(color: accentBlue, fontWeight: FontWeight.bold),
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
                onChanged: _isStreaming
                    ? null
                    : (v) => setState(() => _temperature = v),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Top-K Sampling',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                Text(
                  '$_topK',
                  style:
                      TextStyle(color: accentBlue, fontWeight: FontWeight.bold),
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
                onChanged: _isStreaming
                    ? null
                    : (v) => setState(() => _topK = v.round()),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Max Output Tokens',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                Text(
                  '$_maxTokens',
                  style:
                      TextStyle(color: accentBlue, fontWeight: FontWeight.bold),
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
                onChanged: _isStreaming
                    ? null
                    : (v) => setState(() => _maxTokens = v.round()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomInstructionField(Color surfaceColor, Color accentBlue) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accentBlue.withValues(alpha: 0.5)),
      ),
      child: TextField(
        controller: _customPromptController,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: const InputDecoration(
          labelText: 'Custom Instruction',
          labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
          hintText: 'e.g., Extract the 3 most critical points',
          hintStyle: TextStyle(color: Colors.white38),
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: InputBorder.none,
        ),
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

    final speedText = _tokensPerSecond != null
        ? '${_tokensPerSecond!.toStringAsFixed(1)} est. tok/s'
        : '--';

    final tokensText =
        _estimatedTokenCount > 0 ? '$_estimatedTokenCount' : '--';

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
          _buildMetricColumn('E2E RATE', speedText),
          _buildVerticalDivider(),
          _buildMetricColumn('TOKENS', tokensText),
        ],
      ),
    );
  }

  Widget _buildOutputCard(Color surfaceColor, Color accentBlue) {
    return Container(
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
                      icon: const Icon(Icons.copy_rounded,
                          size: 18, color: Color(0xFF90CAF9)),
                      tooltip: 'Copy Output',
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: _generatedOutput));
                        _showSnackBar('Copied to clipboard.');
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.bookmark_add_rounded,
                          size: 18, color: Color(0xFF90CAF9)),
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
                ? (_isStreaming
                    ? 'Generating initial tokens...'
                    : 'No summary generated yet.')
                : _generatedOutput,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: _generatedOutput.isEmpty ? Colors.white38 : Colors.white,
            ),
          ),
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
