import 'package:flutter/material.dart';

import '../models/benchmark_session.dart';
import '../services/database_service.dart';
import 'benchmark_comparison_screen.dart';
import 'saved_benchmark_detail_screen.dart';

/// Read-only archive of completed benchmark sessions. Tapping a session opens
/// it in [SavedBenchmarkDetailScreen]; nothing here loads a session back into
/// the live benchmark runner. The compare action puts the list into a
/// selection mode where picking two sessions opens
/// [BenchmarkComparisonScreen].
class SavedBenchmarkSessionsScreen extends StatefulWidget {
  const SavedBenchmarkSessionsScreen({super.key});

  @override
  State<SavedBenchmarkSessionsScreen> createState() =>
      _SavedBenchmarkSessionsScreenState();
}

class _SavedBenchmarkSessionsScreenState
    extends State<SavedBenchmarkSessionsScreen> {
  static const Color _bgColor = Color(0xFF121212);
  static const Color _surfaceColor = Color(0xFF1E1E1E);
  static const Color _accentBlue = Color(0xFF90CAF9);

  List<Map<String, Object?>> _sessions = [];
  bool _isLoading = true;
  String? _errorMessage;

  bool _selectionMode = false;

  /// Selected session ids in tap order, capped at two; selecting a third drops
  /// the earlier of the current pair.
  final List<int> _selectedIds = [];

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final sessions =
          await DatabaseService.instance.getBenchmarkSessionSummaries();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sessions = [];
        _isLoading = false;
        _errorMessage = 'Could not load saved sessions: $e';
      });
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(int sessionId) {
    setState(() {
      if (_selectedIds.contains(sessionId)) {
        _selectedIds.remove(sessionId);
        return;
      }
      if (_selectedIds.length == 2) {
        _selectedIds.removeAt(0);
      }
      _selectedIds.add(sessionId);
    });
  }

  Future<void> _openComparison() async {
    if (_selectedIds.length != 2) return;

    final first = _selectedIds[0];
    final second = _selectedIds[1];

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BenchmarkComparisonScreen(
          sessionIdA: first,
          sessionIdB: second,
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _openSession(int sessionId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SavedBenchmarkDetailScreen(sessionId: sessionId),
      ),
    );
  }

  String _formatCompletedAt(Object? rawValue) {
    if (rawValue is! String) return 'Unknown date';
    final parsed = DateTime.tryParse(rawValue);
    if (parsed == null) return 'Unknown date';
    return formatBenchmarkDateTime(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _surfaceColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _selectionMode
              ? 'Select 2 sessions'
              : 'Saved Benchmark Sessions',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: [
          if (_sessions.length >= 2)
            IconButton(
              tooltip: _selectionMode ? 'Cancel' : 'Compare two sessions',
              icon: Icon(
                _selectionMode
                    ? Icons.close_rounded
                    : Icons.compare_arrows_rounded,
                color: _accentBlue,
              ),
              onPressed: _toggleSelectionMode,
            ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
      floatingActionButton: _selectionMode
          ? FloatingActionButton.extended(
              backgroundColor:
                  _selectedIds.length == 2 ? _accentBlue : Colors.white12,
              foregroundColor:
                  _selectedIds.length == 2 ? Colors.black : Colors.white38,
              onPressed: _selectedIds.length == 2 ? _openComparison : null,
              icon: const Icon(Icons.compare_arrows_rounded),
              label: Text('Compare (${_selectedIds.length}/2)'),
            )
          : null,
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

    if (_sessions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inbox_rounded,
                color: Colors.white24,
                size: 48,
              ),
              SizedBox(height: 12),
              Text(
                'No saved benchmark sessions yet.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              SizedBox(height: 6),
              Text(
                'Run the benchmark suite and the completed session will be '
                'saved here automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16.0),
      itemCount: _sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final session = _sessions[index];
        final sessionId = session['id'] as int;
        final modelNames = (session['model_names'] as List?)?.cast<String>() ??
            const <String>[];
        final modelCount = session['model_count'] as int? ?? modelNames.length;
        final runsPerModel = session['runs_per_model'] as int? ?? 0;
        final bool selected = _selectedIds.contains(sessionId);

        return Material(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _selectionMode
                ? _toggleSelection(sessionId)
                : _openSession(sessionId),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? _accentBlue : Colors.white12,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _selectionMode
                            ? (selected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded)
                            : Icons.schedule_rounded,
                        color: _selectionMode && !selected
                            ? Colors.white38
                            : _accentBlue,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _formatCompletedAt(session['completed_at']),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (!_selectionMode)
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white38,
                          size: 20,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$modelCount model${modelCount == 1 ? '' : 's'} · '
                    '$runsPerModel run${runsPerModel == 1 ? '' : 's'} per model',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  if (modelNames.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      modelNames.join(' · '),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}