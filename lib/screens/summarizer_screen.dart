import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/benchmark_test_case.dart';
import '../models/summary_record.dart';
import '../services/database_service.dart';
import '../services/gemini_nano_service.dart';
import '../services/litertlm_service.dart';
import '../services/llama_gguf_service.dart';
import '../services/model_manager_service.dart';
import 'settings_screen.dart';

bool supportsAdjustableSamplingControls(ModelEngine? engine) {
  return engine != ModelEngine.litertlm;
}

class SummarizerScreen extends StatefulWidget {
  const SummarizerScreen({
    super.key,
    required this.modelManager,
    this.scanModelsOnInit = true,
    this.onUseInBenchmark,
  });

  final ModelManagerService modelManager;

  /// Lets focused widget tests render the screen without starting platform
  /// model discovery. Production callers keep the default behavior.
  final bool scanModelsOnInit;

  /// Receives an immutable snapshot of the successful Playground test case.
  /// AppShell uses it to open Benchmark without duplicating editable fields.
  final ValueChanged<BenchmarkTestCase>? onUseInBenchmark;

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

  late final ModelManagerService _modelManager;
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _customPromptController = TextEditingController(
    text: 'Extract the 3 most critical points',
  );
  final ScrollController _scrollController = ScrollController();

  // Inference State
  bool _isStreaming = false;
  String _generatedOutput = '';
  BenchmarkTestCase? _runningTestCase;
  BenchmarkTestCase? _completedTestCase;

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
    _modelManager = widget.modelManager;
    _modelManager.addListener(_onModelManagerStateChanged);
    if (widget.scanModelsOnInit) {
      _modelManager.scanModels();
    }
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
    final engine = _modelManager.activeModel?.engine;
    if (engine == ModelEngine.litertlm) {
      // Native decoding must be stopped explicitly; cancelling only the Dart
      // subscription is not a portable LiteRT-LM cancellation mechanism.
      await LiteRtLmService.instance.stop();
    }

    await _streamSubscription?.cancel();
    _streamSubscription = null;
    if (engine == ModelEngine.gguf) {
      await LlamaGgufService.stop();
    }
    _stopTimers();

    if (mounted) {
      setState(() {
        _isStreaming = false;
        _runningTestCase = null;
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
      _runningTestCase = null;
      _completedTestCase = null;
      _resetMetrics();
    });
    _showSnackBar('Sample passage loaded.');
  }

  void _clearInput() {
    _inputController.clear();
    setState(() {
      _generatedOutput = '';
      _runningTestCase = null;
      _completedTestCase = null;
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

    final String instruction = _selectedInstruction();

    final fullPrompt = buildInferencePrompt(
      format: activeModel.promptFormat,
      instruction: instruction,
      rawText: rawText,
    );

    setState(() {
      _isStreaming = true;
      _generatedOutput = '';
      _runningTestCase = BenchmarkTestCase(
        passage: rawText,
        instruction: instruction,
        source: BenchmarkTestCaseSource.playground,
        taskType: _selectedAction,
      );
      _completedTestCase = null;
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
          maxTokens: _maxTokens,
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
            _completedTestCase = _runningTestCase;
            _runningTestCase = null;
          });
          _autoScroll();
        }
      } catch (e) {
        _stopTimers();
        if (mounted) {
          setState(() {
            _isStreaming = false;
            _runningTestCase = null;
          });
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
        _listenToGenerationStream(stream, engineLabel: 'GGUF');
      } catch (e) {
        _stopTimers();
        if (mounted) {
          setState(() {
            _isStreaming = false;
            _runningTestCase = null;
          });
          _showSnackBar('GGUF Inference Failed: $e');
        }
      }
      return;
    }

    // 3. LiteRT-LM Engine (general GPU backend)
    if (activeModel.engine == ModelEngine.litertlm) {
      try {
        final stream = await LiteRtLmService.instance.generate(
          prompt: fullPrompt,
          maxOutputTokens: _maxTokens,
        );
        _listenToGenerationStream(stream, engineLabel: 'LiteRT-LM');
      } catch (e) {
        _stopTimers();
        if (mounted) {
          setState(() {
            _isStreaming = false;
            _runningTestCase = null;
          });
          _showSnackBar('LiteRT-LM Inference Failed: $e');
        }
      }
      return;
    }

    _stopTimers();
    if (mounted) {
      setState(() {
        _isStreaming = false;
        _runningTestCase = null;
      });
      _showSnackBar('The selected model engine is no longer supported.');
    }
  }

  String _selectedInstruction() {
    if (_selectedAction != 'Custom') {
      return _presetPrompts[_selectedAction] ?? '';
    }

    final String customInstruction = _customPromptController.text.trim();
    return customInstruction.isEmpty
        ? 'Summarize the following passage:'
        : customInstruction;
  }

  void _useInBenchmark() {
    final ValueChanged<BenchmarkTestCase>? callback = widget.onUseInBenchmark;
    final BenchmarkTestCase? testCase = _completedTestCase;
    if (callback == null || testCase == null) return;

    callback(testCase);
  }

  void _listenToGenerationStream(
    Stream<String> stream, {
    required String engineLabel,
  }) {
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
          setState(() {
            _isStreaming = false;
            _runningTestCase = null;
          });
          _showSnackBar('$engineLabel Stream Error: $error');
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
              _tokensPerSecond = _estimatedTokenCount / _totalLatencySeconds!;
            }
            if (_generatedOutput.trim().isNotEmpty) {
              _completedTestCase = _runningTestCase;
            }
            _runningTestCase = null;
          });
        }
      },
      cancelOnError: true,
    );
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
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeModel = _modelManager.activeModel;
    final isReady = activeModel != null && !_modelManager.isLoading;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Playground'),
            const SizedBox(height: 2),
            Text(
              'Local AI Lab · On-device',
              style: theme.textTheme.bodySmall?.copyWith(
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
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _buildModelSelectorCard(),
            const SizedBox(height: 24),
            _buildTaskSection(),
            if (_selectedAction == 'Custom') ...[
              const SizedBox(height: 12),
              _buildCustomInstructionField(),
            ],
            const SizedBox(height: 24),
            _buildInputSection(),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const Key('playground-run-button'),
              onPressed: !isReady
                  ? null
                  : (_isStreaming ? _stopGeneration : _runInference),
              icon: _isStreaming
                  ? const Icon(Icons.stop_circle_outlined)
                  : const Icon(Icons.auto_awesome_outlined),
              label: Text(_isStreaming ? 'Stop generation' : 'Run on device'),
              style: _isStreaming
                  ? FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    )
                  : null,
            ),
            const SizedBox(height: 20),
            _buildOutputCard(),
            const SizedBox(height: 20),
            _buildControlsCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildModelSelectorCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final available = _modelManager.summarizerModels;
    final active = _modelManager.activeModel;
    final isLoading = _modelManager.isLoading;
    final status = _modelManager.statusMessage ?? 'Ready';
    final readyColor = theme.brightness == Brightness.dark
        ? const Color(0xFF81C784)
        : const Color(0xFF2E7D32);

    if (available.isEmpty && !isLoading) {
      return Card(
        key: const Key('playground-model-card'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MODEL',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.error_outline, color: scheme.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(status, style: theme.textTheme.bodyMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Rescan models',
                    onPressed: _modelManager.scanModels,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      key: const Key('playground-model-card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MODEL',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.memory_rounded,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: active?.id,
                      isExpanded: true,
                      icon: const Icon(Icons.expand_more_rounded),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                      items: available.map((model) {
                        return DropdownMenuItem<String>(
                          value: model.id,
                          child: Text(
                            '${model.name} · ${model.formattedSize}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (_isStreaming || isLoading)
                          ? null
                          : (newId) {
                              if (newId != null && newId != active?.id) {
                                final target = available.firstWhere(
                                  (model) => model.id == newId,
                                );
                                _modelManager.loadModel(target);
                              }
                            },
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'Remove model file',
                  onPressed:
                      (_isStreaming ||
                          isLoading ||
                          active == null ||
                          active.engine == ModelEngine.nano)
                      ? null
                      : () => _confirmDeleteModel(active),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  isLoading ? Icons.sync_rounded : Icons.circle,
                  size: isLoading ? 16 : 10,
                  color: active != null && !isLoading
                      ? readyColor
                      : scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    status,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: active != null && !isLoading
                          ? readyColor
                          : scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskSection() {
    final theme = Theme.of(context);
    final descriptions = <String, String>{
      '2-Sentence Summary': 'Exactly two clear, concise sentences',
      'Key Events': 'Significant events, milestones, and timestamps',
      'Action Items': 'Next steps, deliverables, and assignments',
      'Custom': 'Follow the instruction you provide below',
    };

    return Column(
      key: const Key('playground-task-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Task', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildTaskButton('2-Sentence Summary')),
            const SizedBox(width: 12),
            Expanded(child: _buildTaskButton('Key Events')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildTaskButton('Action Items')),
            const SizedBox(width: 12),
            Expanded(child: _buildTaskButton('Custom')),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          descriptions[_selectedAction]!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildTaskButton(String action) {
    final selected = _selectedAction == action;
    final label = action == 'Custom' ? 'Custom instruction' : action;
    final onPressed = _isStreaming
        ? null
        : () => setState(() => _selectedAction = action);

    return Semantics(
      selected: selected,
      child: SizedBox(
        height: 64,
        child: selected
            ? FilledButton.tonal(
                key: Key('playground-task-$action'),
                onPressed: onPressed,
                child: Text(label, textAlign: TextAlign.center),
              )
            : OutlinedButton(
                key: Key('playground-task-$action'),
                onPressed: onPressed,
                child: Text(label, textAlign: TextAlign.center),
              ),
      ),
    );
  }

  Widget _buildInputSection() {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Input', style: theme.textTheme.titleMedium)),
            TextButton.icon(
              key: const Key('playground-paste-button'),
              onPressed: _isStreaming ? null : _pasteFromClipboard,
              icon: const Icon(Icons.content_paste_outlined, size: 20),
              label: const Text('Paste'),
            ),
            TextButton.icon(
              key: const Key('playground-sample-button'),
              onPressed: _isStreaming ? null : _loadSamplePassage,
              icon: const Icon(Icons.description_outlined, size: 20),
              label: const Text('Sample'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('playground-input-field'),
          controller: _inputController,
          minLines: 5,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: 'Enter or paste text here…',
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _inputController,
              builder: (_, value, __) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Clear input',
                  onPressed: _isStreaming ? null : _clearInput,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteModel(ModelInfo model) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
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

    final bool removed = await _modelManager.deleteModel(model);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed
              ? 'Removed ${model.name}.'
              : _modelManager.statusMessage ?? 'Could not remove the model.',
        ),
      ),
    );
  }

  Widget _buildControlsCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bool samplingControlsAvailable = supportsAdjustableSamplingControls(
      _modelManager.activeModel?.engine,
    );
    final String controlsSummary = samplingControlsAvailable
        ? 'T ${_temperature.toStringAsFixed(2)} · K $_topK · Max $_maxTokens'
        : 'T fixed · K fixed · Max $_maxTokens';

    return Card(
      key: const Key('playground-runtime-controls'),
      margin: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Icon(Icons.tune_rounded, color: scheme.primary),
          title: Text('Runtime controls', style: theme.textTheme.titleMedium),
          subtitle: Text(
            controlsSummary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          children: [
            _buildControlLabel(
              'Temperature',
              samplingControlsAvailable
                  ? _temperature.toStringAsFixed(2)
                  : '${LiteRtLmService.fixedGpuTemperature.toStringAsFixed(2)} (fixed)',
              enabled: samplingControlsAvailable,
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: scheme.primary,
                thumbColor: scheme.primary,
              ),
              child: Slider(
                value: samplingControlsAvailable
                    ? _temperature
                    : LiteRtLmService.fixedGpuTemperature,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: _isStreaming || !samplingControlsAvailable
                    ? null
                    : (v) => setState(() => _temperature = v),
              ),
            ),
            _buildControlLabel(
              'Top-K Sampling',
              samplingControlsAvailable
                  ? '$_topK'
                  : '${LiteRtLmService.fixedGpuTopK} (fixed)',
              enabled: samplingControlsAvailable,
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: scheme.primary,
                thumbColor: scheme.primary,
              ),
              child: Slider(
                value: samplingControlsAvailable
                    ? _topK.toDouble()
                    : LiteRtLmService.fixedGpuTopK.toDouble(),
                min: 1,
                max: 40,
                divisions: 39,
                onChanged: _isStreaming || !samplingControlsAvailable
                    ? null
                    : (v) => setState(() => _topK = v.round()),
              ),
            ),
            if (!samplingControlsAvailable) ...[
              const SizedBox(height: 2),
              const Text(
                'LiteRT-LM 0.16 GPU sampling is fixed by the native runtime '
                '(effectively greedy). Temperature and Top-K cannot be '
                'changed; Max Output Tokens remains available.',
              ),
              const SizedBox(height: 12),
            ],
            _buildControlLabel('Max Output Tokens', '$_maxTokens'),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: scheme.primary,
                thumbColor: scheme.primary,
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

  Widget _buildControlLabel(String label, String value, {bool enabled = true}) {
    final theme = Theme.of(context);
    final valueColor = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Row(
      children: [
        Flexible(
          flex: 2,
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.labelLarge?.copyWith(color: valueColor),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomInstructionField() {
    return TextField(
      key: const Key('playground-custom-instruction'),
      controller: _customPromptController,
      minLines: 1,
      maxLines: 3,
      decoration: const InputDecoration(
        labelText: 'Custom instruction',
        hintText: 'For example: Extract the 3 most critical points',
      ),
    );
  }

  Widget _buildOutputCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final activeModel = _modelManager.activeModel;
    final readyColor = theme.brightness == Brightness.dark
        ? const Color(0xFF81C784)
        : const Color(0xFF2E7D32);
    final statusText = _isStreaming
        ? 'Generating locally'
        : (_generatedOutput.isNotEmpty
              ? 'Completed locally'
              : 'Ready for an on-device run');

    final latencyText = _totalLatencySeconds != null
        ? '${_totalLatencySeconds!.toStringAsFixed(2)}s'
        : (_isStreaming
              ? '${(_inferenceStopwatch.elapsedMilliseconds / 1000.0).toStringAsFixed(1)}s'
              : '--');

    final ttftText = _timeToFirstTokenSeconds != null
        ? '${_timeToFirstTokenSeconds!.toStringAsFixed(2)}s'
        : '--';

    final speedText = _tokensPerSecond != null
        ? _tokensPerSecond!.toStringAsFixed(1)
        : '--';
    final speedUnit = _tokensPerSecond != null ? 'est. tok/s' : null;

    final tokensText = _estimatedTokenCount > 0
        ? '$_estimatedTokenCount'
        : '--';

    return Card(
      key: const Key('playground-output-card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Output', style: theme.textTheme.titleLarge),
                ),
                if (activeModel != null)
                  Flexible(
                    child: Text(
                      activeModel.name,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              statusText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _generatedOutput.isNotEmpty || _isStreaming
                    ? readyColor
                    : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            SelectableText(
              _generatedOutput.isEmpty
                  ? (_isStreaming
                        ? 'Generating initial tokens…'
                        : 'Your generated output will appear here.')
                  : _generatedOutput,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.5,
                color: _generatedOutput.isEmpty
                    ? scheme.onSurfaceVariant
                    : scheme.onSurface,
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildMetricColumn('TTFT', ttftText)),
                const SizedBox(width: 8),
                Expanded(child: _buildMetricColumn('LATENCY', latencyText)),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricColumn('RATE', speedText, unit: speedUnit),
                ),
                const SizedBox(width: 8),
                Expanded(child: _buildMetricColumn('TOKENS', tokensText)),
              ],
            ),
            if (_generatedOutput.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copy'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _generatedOutput));
                      _showSnackBar('Copied to clipboard.');
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Save'),
                    onPressed: _saveCurrentSummary,
                  ),
                  if (widget.onUseInBenchmark != null &&
                      _completedTestCase != null)
                    TextButton.icon(
                      key: const Key('playground-use-in-benchmark'),
                      icon: const Icon(Icons.compare_arrows_rounded),
                      label: const Text('Use in Benchmark'),
                      onPressed: _useInBenchmark,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricColumn(String label, String value, {String? unit}) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          height: 28,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                color: value == '--'
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
        if (unit != null) ...[
          const SizedBox(height: 2),
          Text(
            unit,
            maxLines: 1,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
