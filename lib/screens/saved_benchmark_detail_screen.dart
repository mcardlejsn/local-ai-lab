import 'package:flutter/material.dart';

import '../models/benchmark_session.dart';
import '../services/database_service.dart';
import '../widgets/benchmark_results_table.dart';

/// View of one saved benchmark session. Shows the session's passage,
/// instruction, and comparative results exactly as recorded. Nothing here runs
/// inference or alters a recorded result; the only writable field is the manual
/// accuracy score attached to a run.
class SavedBenchmarkDetailScreen extends StatefulWidget {
  const SavedBenchmarkDetailScreen({
    super.key,
    required this.sessionId,
  });

  final int sessionId;

  @override
  State<SavedBenchmarkDetailScreen> createState() =>
      _SavedBenchmarkDetailScreenState();
}

class _SavedBenchmarkDetailScreenState
    extends State<SavedBenchmarkDetailScreen> {
  static const Color _bgColor = Color(0xFF121212);
  static const Color _surfaceColor = Color(0xFF1E1E1E);
  static const Color _accentBlue = Color(0xFF90CAF9);

  bool _isLoading = true;
  String? _errorMessage;

  String _passage = '';
  String _instruction = '';
  int _runsPerModel = 0;
  DateTime? _completedAt;
  List<BenchmarkAggregate> _aggregates = [];

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      final saved = await DatabaseService.instance
          .getCompletedBenchmarkById(widget.sessionId);

      if (!mounted) return;

      if (saved == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'That saved session could not be found.';
        });
        return;
      }

      final runMaps = (saved['runs'] as List).cast<Map<String, Object?>>();

      setState(() {
        _passage = saved['passage'] as String;
        _instruction = saved['instruction'] as String;
        _runsPerModel = saved['runs_per_model'] as int;
        _completedAt =
            DateTime.parse(saved['completed_at'] as String).toLocal();
        _aggregates = buildAggregatesFromSavedRuns(runMaps);
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load this saved session: $e';
      });
    }
  }

  /// Persists a manual score for one saved run, then reloads the session so the
  /// table's medians reflect it.
  Future<void> _handleScoreRun(
    BenchmarkModelResult run,
    int? score,
    String? note,
  ) async {
    final runId = run.runId;
    if (runId == null) return;

    try {
      await DatabaseService.instance.updateBenchmarkRunScore(
        runId: runId,
        accuracyScore: score,
        scoreNote: note,
      );
      await _loadSession();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save that score: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _surfaceColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Saved Benchmark',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _accentBlue),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
          ),
        ),
      );
    }

    final modelCount = _aggregates.length;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: _accentBlue,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _completedAt == null
                          ? 'Completed date unknown'
                          : 'Completed ${formatBenchmarkDateTime(_completedAt!)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$modelCount model${modelCount == 1 ? '' : 's'} · '
                      '$_runsPerModel run${_runsPerModel == 1 ? '' : 's'} per model',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Benchmark Instruction:',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 6),
        _buildReadOnlyBlock(_instruction),
        const SizedBox(height: 12),
        const Text(
          'Passage:',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 6),
        _buildReadOnlyBlock(_passage),
        const SizedBox(height: 20),
        const Text(
          'Comparative Results:',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        if (_aggregates.isEmpty)
          const Text(
            'This session has no saved run records.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          )
        else
          BenchmarkResultsTable(
            aggregates: _aggregates,
            onScoreRun: _handleScoreRun,
          ),
      ],
    );
  }

  Widget _buildReadOnlyBlock(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: SelectableText(
        text.isEmpty ? '(Empty)' : text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          height: 1.4,
        ),
      ),
    );
  }
}