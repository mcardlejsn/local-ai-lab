import 'package:flutter/material.dart';

import '../services/database_service.dart';

/// Read-only archive of completed benchmark sessions.
///
/// Pops with the selected session's id (an `int`), or with `null` if the user
/// backs out. Loading the full session is left to the caller.
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

  String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final year = value.year.toString();
    final minute = value.minute.toString().padLeft(2, '0');
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final period = value.hour < 12 ? 'AM' : 'PM';
    return '$month/$day/$year $hour12:$minute $period';
  }

  String _formatCompletedAt(Object? rawValue) {
    if (rawValue is! String) return 'Unknown date';
    final parsed = DateTime.tryParse(rawValue);
    if (parsed == null) return 'Unknown date';
    return _formatDateTime(parsed.toLocal());
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
          'Saved Benchmark Sessions',
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
        final modelNames =
            (session['model_names'] as List?)?.cast<String>() ?? const <String>[];
        final modelCount = session['model_count'] as int? ?? modelNames.length;
        final runsPerModel = session['runs_per_model'] as int? ?? 0;

        return Material(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.pop(context, sessionId),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        color: _accentBlue,
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