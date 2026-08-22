import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import '../models/summary_record.dart';
import '../services/database_service.dart';
import 'history_screen.dart';

class SummarizerScreen extends StatefulWidget {
  const SummarizerScreen({super.key});

  @override
  State<SummarizerScreen> createState() => _SummarizerScreenState();
}

class _SummarizerScreenState extends State<SummarizerScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  InferenceModel? _model;
  InferenceModelSession? _currentSession;
  StreamSubscription<String>? _responseSubscription;

  String _streamedOutput = '';
  bool _isGenerating = false;
  String _activeTask = '';
  String _lastProcessedInput = '';

  @override
  void dispose() {
    _responseSubscription?.cancel();
    _currentSession?.stopGeneration();
    _currentSession?.close();
    _model?.close();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _cleanResponse(String text) {
    return text.replaceAll(RegExp(r'^TextResponse\(|\)$'), '').trim();
  }

  Future<void> _cleanupSession() async {
    await _responseSubscription?.cancel();
    _responseSubscription = null;
    if (_currentSession != null) {
      await _currentSession!.close();
      _currentSession = null;
    }
  }

  Future<void> _cancelGeneration() async {
    if (_currentSession != null) {
      await _currentSession!.stopGeneration();
    }
    await _cleanupSession();
    if (mounted) {
      setState(() {
        _isGenerating = false;
        _activeTask = '';
      });
    }
  }

  Future<InferenceModel> _getModel() async {
    if (_model != null) return _model!;
    _model = await FlutterGemma.getActiveModel(maxTokens: 1024);
    return _model!;
  }

  Future<void> _executeStreamingInference(String taskName, String systemPrompt) async {
    final rawInput = _inputController.text.trim();
    if (rawInput.isEmpty || _isGenerating) return;

    FocusScope.of(context).unfocus();
    await _cancelGeneration();

    setState(() {
      _isGenerating = true;
      _activeTask = taskName;
      _streamedOutput = '';
      _lastProcessedInput = rawInput;
    });

    final prompt = '$systemPrompt\n\nText:\n$rawInput\n\nResponse:';

    try {
      final model = await _getModel();
      _currentSession = await model.createSession();
      await _currentSession!.addQueryChunk(Message(text: prompt, isUser: true));

      final stream = _currentSession!.getResponseAsync();

      _responseSubscription = stream.listen(
        (chunk) {
          if (chunk.isNotEmpty) {
            setState(() {
              _streamedOutput += chunk;
            });
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOut,
              );
            }
          }
        },
        onError: (error) {
          setState(() {
            _streamedOutput = 'Inference error: ${error.toString()}';
            _isGenerating = false;
            _activeTask = '';
          });
          _cleanupSession();
        },
        onDone: () {
          setState(() {
            _streamedOutput = _cleanResponse(_streamedOutput);
            _isGenerating = false;
            _activeTask = '';
          });
          _cleanupSession();
        },
        cancelOnError: true,
      );
    } catch (e) {
      setState(() {
        _streamedOutput = 'Execution failure: ${e.toString()}';
        _isGenerating = false;
        _activeTask = '';
      });
      await _cleanupSession();
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() {
        _inputController.text = data!.text!;
      });
    }
  }

  void _clearAll() {
    _cancelGeneration();
    setState(() {
      _inputController.clear();
      _streamedOutput = '';
      _lastProcessedInput = '';
    });
  }

  Future<void> _copyOutput() async {
    if (_streamedOutput.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: _streamedOutput));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Summary copied to clipboard', style: TextStyle(fontSize: 16)),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      }
    }
  }

  Future<void> _saveCurrentSummary() async {
    if (_streamedOutput.isEmpty || _lastProcessedInput.isEmpty) return;

    final record = SummaryRecord(
      originalText: _lastProcessedInput,
      generatedSummary: _streamedOutput,
      taskType: _activeTask.isNotEmpty ? _activeTask : 'Summary',
      createdAt: DateTime.now(),
    );

    await DatabaseService.instance.insertSummary(record);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved to offline storage', style: TextStyle(fontSize: 16)),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
    }
  }

  void _navigateToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HistoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bgDark = Color(0xFF121212);
    const surfaceDark = Color(0xFF1E1E1E);
    const borderHighContrast = Color(0xFF888888);
    const primaryAccent = Color(0xFF90CAF9);
    const textHighContrast = Color(0xFFFFFFFF);

    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        title: const Text(
          'Local AI Summarizer',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textHighContrast),
        ),
        backgroundColor: surfaceDark,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.history, size: 28, color: primaryAccent),
            tooltip: 'Saved History',
            onPressed: _navigateToHistory,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep, size: 28, color: Color(0xFFFF8A80)),
            tooltip: 'Clear All',
            onPressed: _clearAll,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Input Area
              Container(
                decoration: BoxDecoration(
                  color: surfaceDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderHighContrast, width: 1.5),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: _inputController,
                      maxLines: 5,
                      style: const TextStyle(fontSize: 17, color: textHighContrast, height: 1.4),
                      decoration: const InputDecoration(
                        hintText: 'Enter or paste raw text/notes here...',
                        hintStyle: TextStyle(color: Color(0xFFAAAAAA), fontSize: 16),
                        border: InputBorder.none,
                      ),
                    ),
                    const Divider(color: borderHighContrast, height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _pasteFromClipboard,
                          icon: const Icon(Icons.paste, size: 20),
                          label: const Text('Paste', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF333333),
                            foregroundColor: primaryAccent,
                            side: const BorderSide(color: borderHighContrast),
                          ),
                        ),
                        if (_isGenerating)
                          OutlinedButton.icon(
                            onPressed: _cancelGeneration,
                            icon: const Icon(Icons.stop, color: Color(0xFFFF5252), size: 20),
                            label: const Text('Stop', style: TextStyle(color: Color(0xFFFF5252), fontSize: 16)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFFF5252), width: 1.5),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Task Buttons
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildTaskButton(
                    label: '2-Sentence Summary',
                    icon: Icons.short_text,
                    taskName: '2-Sentence',
                    systemPrompt: 'Summarize the following text accurately in exactly two clear sentences.',
                  ),
                  _buildTaskButton(
                    label: 'Key Events',
                    icon: Icons.event_note,
                    taskName: 'Events',
                    systemPrompt: 'Extract chronological key events and observations from the text as bullet points.',
                  ),
                  _buildTaskButton(
                    label: 'Action Items',
                    icon: Icons.checklist,
                    taskName: 'Actions',
                    systemPrompt: 'Extract all pending tasks, action items, and next steps from the text as a numbered list.',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Output Area
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: surfaceDark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isGenerating ? primaryAccent : borderHighContrast,
                      width: _isGenerating ? 2.0 : 1.5,
                    ),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                _isGenerating ? 'Generating ($_activeTask)...' : 'Output Result',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _isGenerating ? primaryAccent : textHighContrast,
                                ),
                              ),
                              if (_isGenerating) ...[
                                const SizedBox(width: 10),
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(primaryAccent),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (_streamedOutput.isNotEmpty && !_isGenerating)
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.bookmark_add, size: 24, color: Color(0xFF81C784)),
                                  tooltip: 'Save Summary',
                                  onPressed: _saveCurrentSummary,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 22, color: primaryAccent),
                                  tooltip: 'Copy Output',
                                  onPressed: _copyOutput,
                                ),
                              ],
                            ),
                        ],
                      ),
                      const Divider(color: borderHighContrast, height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          child: SelectableText(
                            _streamedOutput.isEmpty
                                ? (_isGenerating ? 'Awaiting first token...' : 'Generated output will stream here.')
                                : _streamedOutput,
                            style: TextStyle(
                              fontSize: 17,
                              color: _streamedOutput.isEmpty ? const Color(0xFF888888) : textHighContrast,
                              height: 1.5,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskButton({
    required String label,
    required IconData icon,
    required String taskName,
    required String systemPrompt,
  }) {
    final isSelected = _isGenerating && _activeTask == taskName;
    return ElevatedButton.icon(
      onPressed: _isGenerating ? null : () => _executeStreamingInference(taskName, systemPrompt),
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? const Color(0xFF1565C0) : const Color(0xFF263238),
        foregroundColor: const Color(0xFFFFFFFF),
        disabledBackgroundColor: const Color(0xFF1E1E1E),
        disabledForegroundColor: const Color(0xFF666666),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        side: BorderSide(
          color: isSelected ? const Color(0xFF90CAF9) : const Color(0xFF546E7A),
          width: 1.5,
        ),
      ),
    );
  }
}