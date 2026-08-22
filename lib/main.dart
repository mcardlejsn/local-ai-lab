import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize(inferenceEngines: const [MediaPipeEngine()]);
  runApp(const LocalAiApp());
}

class LocalAiApp extends StatelessWidget {
  const LocalAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local AI Summarizer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF90CAF9),
          surface: Color(0xFF1E1E1E),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(fontSize: 18.0, color: Color(0xFFE0E0E0), height: 1.4),
          titleMedium: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      home: const SummarizerScreen(),
    );
  }
}

class SummarizerScreen extends StatefulWidget {
  const SummarizerScreen({super.key});

  @override
  State<SummarizerScreen> createState() => _SummarizerScreenState();
}

class _SummarizerScreenState extends State<SummarizerScreen> {
  final TextEditingController _textController = TextEditingController(
    text: 'Client had a steady morning routine. Completed breakfast and took scheduled 9:00 AM medications without issue. Expressed mild frustration during afternoon transition to physical therapy, but calmed down after a 10-minute quiet break in the sensory room. Ate full dinner at 5:30 PM. Hydration tracked at 1800ml for the shift. Handover given to evening staff.',
  );

  InferenceModel? _model;
  bool _isModelLoaded = false;
  bool _isGenerating = false;
  String _status = 'Loading local model...';
  String _summaryOutput = '';

  @override
  void initState() {
    super.initState();
    _initModel();
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

  Future<void> _executePrompt(String promptInstruction) async {
    final text = _textController.text.trim();
    if (_model == null || text.isEmpty) return;

    setState(() {
      _isGenerating = true;
      _summaryOutput = '';
    });

    FocusScope.of(context).unfocus();

    try {
      final chat = await _model!.createChat();
      final fullPrompt = '$promptInstruction\n\nText:\n$text\n\nResponse:';
      
      await chat.addQueryChunk(
        Message.text(
          text: fullPrompt,
          isUser: true,
        ),
      );

      final response = await chat.generateChatResponse();
      
      String parsedText = response.toString().trim();
      final match = RegExp(r'^TextResponse\("?(.*)"?\)$', dotAll: true).firstMatch(parsedText);
      if (match != null && match.group(1) != null) {
        parsedText = match.group(1)!;
      }
      parsedText = parsedText.replaceAll(r'\n', '\n').trim();

      setState(() {
        _summaryOutput = parsedText.isEmpty ? 'No output generated.' : parsedText;
      });
    } catch (e) {
      setState(() => _summaryOutput = 'Inference Error: $e');
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  @override
  void dispose() {
    _model?.close();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Local AI Summarizer',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
                _textController.text = data!.text!;
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Clear text',
            onPressed: () => _textController.clear(),
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
                  onPressed: (!_isModelLoaded || _isGenerating)
                      ? null
                      : () => _executePrompt('Summarize the key information from the following text into exactly two concise sentences:'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.checklist, size: 20),
                  label: const Text('Extract Key Events', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF81C784),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: (!_isModelLoaded || _isGenerating)
                      ? null
                      : () => _executePrompt('Extract the key events and facts from the following text as a numbered bullet list:'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.flash_on, size: 20),
                  label: const Text('Action Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB74D),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: (!_isModelLoaded || _isGenerating)
                      ? null
                      : () => _executePrompt('Identify all action items, follow-ups, or required next steps from the following text:'),
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
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    tooltip: 'Copy output',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _summaryOutput));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)),
                      );
                    },
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
              child: _isGenerating
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
                      style: const TextStyle(fontSize: 18.0, height: 1.45, color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}