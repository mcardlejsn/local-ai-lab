import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import '../models/summary_record.dart';
import '../services/database_service.dart';
import 'history_screen.dart';

class SummarizerScreen extends StatefulWidget {
  const SummarizerScreen({super.key});

  @override
  State<SummarizerScreen> createState() => _SummarizerScreenState();
}

class _SummarizerScreenState extends State<SummarizerScreen> {
  final TextEditingController _textController = TextEditingController(
    text:
        'Client had a steady morning routine. Completed breakfast and took scheduled 9:00 AM medications without issue. Expressed mild frustration during afternoon transition to physical therapy, but calmed down after a 10-minute quiet break in the sensory room. Ate full dinner at 5:30 PM. Hydration tracked at 1800ml for the shift. Handover given to evening staff.',
  );
  final TextEditingController _customPresetController =
      TextEditingController(text: 'Extract the 3 most critical points as bullet items');

  InferenceModel? _model;
  bool _isModelLoaded = false;
  bool _isGenerating = false;
  bool _isSaved = false;
  String _status = 'Loading local model...';
  String _activeTask = '2-Sentence Summary';
  String _summaryOutput = '';

  double _temperature = 0.2;
  int _topK = 40;

  @override
  void initState() {
    super.initState();
    _initModel();
  }

  @override
  void dispose() {
    _model?.close();
    _textController.dispose();
    _customPresetController.dispose();
    super.dispose();
  }

  Future<String> _getModelPath() async {
    final dir = await getExternalStorageDirectory();
    return '${dir?.path}/gemma-2b-it-cpu-int4.bin';
  }

  Future<void> _initModel() async {
    final path = await _getModelPath();
    final file = File(path);

    if (!await file.exists()) {
      setState(() {
        _status = 'Model file not found in sandbox.';
      });
      return;
    }

    try {
      await FlutterGemma.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.binary,
      ).fromFile(path).install();

      _model = await FlutterGemma.getActiveModel(maxTokens: 512);

      setState(() {
        _isModelLoaded = true;
        _status = 'Engine Ready (100% Offline)';
      });
    } catch (e) {
      setState(() => _status = 'Load failed: $e');
    }
  }

  String _buildPrompt(String task, String text) {
    switch (task) {
      case '2-Sentence Summary':
        return 'Summarize the key information from the following text into exactly two concise sentences:\n\nText:\n$text\n\nResponse:';
      case 'Key Events':
        return 'Extract the key events and facts from the following text as a numbered bullet list:\n\nText:\n$text\n\nResponse:';
      case 'Action Items':
        return 'Identify all action items, follow-ups, or required next steps from the following text:\n\nText:\n$text\n\nResponse:';
      case 'Custom':
        final instruction = _customPresetController.text.trim().isNotEmpty
            ? _customPresetController.text.trim()
            : 'Summarize the following text';
        return '$instruction:\n\nText:\n$text\n\nResponse:';
      default:
        return 'Summarize the following text:\n\nText:\n$text\n\nResponse:';
    }
  }

  Future<void> _executePrompt(String task) async {
    final text = _textController.text.trim();
    if (_model == null || text.isEmpty || _isGenerating) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _activeTask = task;
      _isGenerating = true;
      _summaryOutput = '';
      _isSaved = false;
    });

    try {
      final session = await _model!.createSession(
        temperature: _temperature,
        randomSeed: 1,
        topK: _topK,
      );

      final fullPrompt = _buildPrompt(task, text);
      await session.addQueryChunk(
        Message.text(
          text: fullPrompt,
          isUser: true,
        ),
      );

      final stream = session.getResponseAsync();
      await for (final token in stream) {
        if (!mounted) break;
        setState(() {
          _summaryOutput += token;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _summaryOutput = 'Inference Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _saveToDatabase() async {
    if (_summaryOutput.trim().isEmpty || _isSaved) return;

    final taskLabel = _activeTask == 'Custom'
        ? 'Custom (${_customPresetController.text.trim()})'
        : _activeTask;

    final record = SummaryRecord(
      originalText: _textController.text.trim(),
      generatedSummary: _summaryOutput.trim(),
      taskType: taskLabel,
      createdAt: DateTime.now(),
    );

    await DatabaseService.instance.insertSummary(record);
    if (!mounted) return;
    setState(() {
      _isSaved = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Summary saved to local database'),
        backgroundColor: Color(0xFF1E1E1E),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        backgroundColor: Color(0xFF1E1E1E),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Local AI Summarizer',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.paste),
            tooltip: 'Paste from clipboard',
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              if (data?.text != null) {
                setState(() {
                  _textController.text = data!.text!;
                });
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Clear text',
            onPressed: () {
              setState(() {
                _textController.clear();
                _summaryOutput = '';
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.history, color: Color(0xFF90CAF9)),
            tooltip: 'Saved History',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18.0),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(
                  color: _isModelLoaded ? const Color(0xFF81C784) : const Color(0xFFE57373),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isModelLoaded ? Icons.offline_bolt : Icons.sync,
                    color: _isModelLoaded ? const Color(0xFF81C784) : const Color(0xFFE57373),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _status,
                      style: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16.0),
            const Text(
              'Input Note / Passage:',
              style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8.0),
            TextField(
              controller: _textController,
              maxLines: 6,
              style: const TextStyle(fontSize: 17.0, height: 1.4),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                hintText: 'Enter or paste text to process offline...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: const BorderSide(color: Color(0xFF424242)),
                ),
                contentPadding: const EdgeInsets.all(14.0),
              ),
            ),
            const SizedBox(height: 12.0),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: const Color(0xFF424242)),
                ),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 14.0),
                  iconColor: const Color(0xFF90CAF9),
                  collapsedIconColor: Colors.grey,
                  title: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Model Controls',
                          style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'T: ${_temperature.toStringAsFixed(2)} | K: $_topK',
                        style: const TextStyle(
                          color: Color(0xFF90CAF9),
                          fontSize: 13.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Temperature', style: TextStyle(color: Color(0xFFCCCCCC))),
                              Text(
                                _temperature.toStringAsFixed(2),
                                style: const TextStyle(
                                  color: Color(0xFF90CAF9),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _temperature,
                            min: 0.0,
                            max: 1.0,
                            divisions: 20,
                            activeColor: const Color(0xFF90CAF9),
                            inactiveColor: const Color(0xFF333333),
                            onChanged: (val) => setState(() => _temperature = val),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Top-K Sampling', style: TextStyle(color: Color(0xFFCCCCCC))),
                              Text(
                                '$_topK',
                                style: const TextStyle(
                                  color: Color(0xFF90CAF9),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: _topK.toDouble(),
                            min: 1,
                            max: 40,
                            divisions: 39,
                            activeColor: const Color(0xFF90CAF9),
                            inactiveColor: const Color(0xFF333333),
                            onChanged: (val) => setState(() => _topK = val.toInt()),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Custom Preset Instruction:',
                            style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _customPresetController,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: const Color(0xFF121212),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.0),
                                borderSide: const BorderSide(color: Color(0xFF424242)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16.0),
            const Text(
              'Select AI Action:',
              style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10.0),
            Wrap(
              spacing: 10.0,
              runSpacing: 10.0,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.summarize, size: 20),
                  label: const Text('2-Sentence Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF90CAF9),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: (!_isModelLoaded || _isGenerating) ? null : () => _executePrompt('2-Sentence Summary'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.checklist, size: 20),
                  label: const Text('Extract Key Events', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF81C784),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: (!_isModelLoaded || _isGenerating) ? null : () => _executePrompt('Key Events'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.flash_on, size: 20),
                  label: const Text('Action Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB74D),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: (!_isModelLoaded || _isGenerating) ? null : () => _executePrompt('Action Items'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.tune, size: 20),
                  label: const Text('Run Custom Preset', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCE93D8),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: (!_isModelLoaded || _isGenerating) ? null : () => _executePrompt('Custom'),
                ),
              ],
            ),
            const SizedBox(height: 22.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Output:',
                  style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
                ),
                if (_summaryOutput.isNotEmpty)
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: 'Copy output',
                        onPressed: () => _copyToClipboard(_summaryOutput),
                      ),
                      IconButton(
                        icon: Icon(
                          _isSaved ? Icons.bookmark : Icons.bookmark_border,
                          size: 20,
                          color: _isSaved ? const Color(0xFF90CAF9) : Colors.grey,
                        ),
                        tooltip: 'Save summary',
                        onPressed: _saveToDatabase,
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8.0),
            Container(
              padding: const EdgeInsets.all(16.0),
              constraints: const BoxConstraints(minHeight: 120.0),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: const Color(0xFF424242)),
              ),
              child: _isGenerating && _summaryOutput.isEmpty
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF90CAF9)),
                        ),
                        SizedBox(width: 14),
                        Text('Running offline inference...', style: TextStyle(fontSize: 17, color: Colors.white70)),
                      ],
                    )
                  : Text(
                      _summaryOutput.isEmpty ? 'AI summary will appear here.' : _summaryOutput,
                      style: TextStyle(
                        fontSize: 18.0,
                        height: 1.45,
                        color: _summaryOutput.isEmpty ? Colors.grey : Colors.white,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}