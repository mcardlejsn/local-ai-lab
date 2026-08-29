import 'package:flutter/material.dart';

import '../models/benchmark_session.dart';
import '../services/database_service.dart';
import 'benchmark_comparison_screen.dart';
import 'saved_benchmark_detail_screen.dart';

/// Read-only archive of completed benchmark sessions.
///
/// Session details, deletion, and two-session comparison retain their existing
/// behavior whether this archive is standalone or embedded in Results.
class SavedBenchmarkSessionsScreen extends StatefulWidget {
  const SavedBenchmarkSessionsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<SavedBenchmarkSessionsScreen> createState() =>
      _SavedBenchmarkSessionsScreenState();
}

class _SavedBenchmarkSessionsScreenState
    extends State<SavedBenchmarkSessionsScreen> {
  List<Map<String, Object?>> _sessions = <Map<String, Object?>>[];
  bool _isLoading = true;
  String? _errorMessage;
  bool _selectionMode = false;
  final List<int> _selectedIds = <int>[];

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final List<Map<String, Object?>> sessions = await DatabaseService.instance
          .getBenchmarkSessionSummaries();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sessions = <Map<String, Object?>>[];
        _isLoading = false;
        _errorMessage = 'Could not load saved sessions: $error';
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
      if (_selectedIds.remove(sessionId)) return;
      if (_selectedIds.length == 2) _selectedIds.removeAt(0);
      _selectedIds.add(sessionId);
    });
  }

  Future<void> _openComparison() async {
    if (_selectedIds.length != 2) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BenchmarkComparisonScreen(
          sessionIdA: _selectedIds[0],
          sessionIdB: _selectedIds[1],
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
      MaterialPageRoute<void>(
        builder: (_) => SavedBenchmarkDetailScreen(sessionId: sessionId),
      ),
    );
  }

  Future<void> _confirmDeleteSession(
    int sessionId,
    String completedLabel,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete this session?'),
        content: Text(
          'The session from $completedLabel and all of its runs will be '
          'removed. This cannot be undone.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    String message;
    try {
      await DatabaseService.instance.deleteBenchmarkSession(sessionId);
      message = 'Session deleted.';
    } catch (error) {
      message = 'Could not delete the session: $error';
    }

    _selectedIds.remove(sessionId);
    await _loadSessions();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatCompletedAt(Object? rawValue) {
    if (rawValue is! String) return 'Unknown date';
    final DateTime? parsed = DateTime.tryParse(rawValue);
    if (parsed == null) return 'Unknown date';
    return formatBenchmarkDateTime(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = Column(
      children: [
        if (widget.embedded) _buildEmbeddedHeader(),
        Expanded(child: _buildBody()),
        if (_selectionMode) _buildComparisonAction(),
      ],
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode ? 'Select 2 sessions' : 'Saved benchmark sessions',
        ),
        actions: [
          if (_sessions.length >= 2)
            IconButton(
              tooltip: _selectionMode ? 'Cancel comparison' : 'Compare',
              icon: Icon(
                _selectionMode
                    ? Icons.close_rounded
                    : Icons.compare_arrows_rounded,
              ),
              onPressed: _toggleSelectionMode,
            ),
        ],
      ),
      body: SafeArea(child: content),
    );
  }

  Widget _buildEmbeddedHeader() {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectionMode
                      ? 'Select 2 sessions'
                      : 'Saved benchmark sessions',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_sessions.length} saved '
                  '${_sessions.length == 1 ? 'session' : 'sessions'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (_sessions.length >= 2)
            TextButton.icon(
              onPressed: _toggleSelectionMode,
              icon: Icon(
                _selectionMode
                    ? Icons.close_rounded
                    : Icons.compare_arrows_rounded,
              ),
              label: Text(_selectionMode ? 'Cancel' : 'Compare'),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final ThemeData theme = Theme.of(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      );
    }
    if (_sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inbox_outlined,
                color: theme.colorScheme.onSurfaceVariant,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'No saved benchmark sessions yet.',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Completed benchmark sessions will be saved here '
                'automatically.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      key: const PageStorageKey<String>('benchmark-results-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: _sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (BuildContext context, int index) {
        return _buildSessionCard(_sessions[index]);
      },
    );
  }

  Widget _buildSessionCard(Map<String, Object?> session) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final int sessionId = session['id'] as int;
    final List<String> modelNames =
        (session['model_names'] as List?)?.cast<String>() ?? <String>[];
    final int modelCount = session['model_count'] as int? ?? modelNames.length;
    final int runsPerModel = session['runs_per_model'] as int? ?? 0;
    final bool selected = _selectedIds.contains(sessionId);
    final String completedLabel = _formatCompletedAt(session['completed_at']);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: selected
            ? BorderSide(color: colors.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _selectionMode
            ? _toggleSelection(sessionId)
            : _openSession(sessionId),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _selectionMode
                        ? selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded
                        : Icons.speed_outlined,
                    color: selected || !_selectionMode
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      completedLabel,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (!_selectionMode)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      color: colors.error,
                      tooltip: 'Delete session',
                      onPressed: () =>
                          _confirmDeleteSession(sessionId, completedLabel),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '$modelCount ${modelCount == 1 ? 'model' : 'models'} · '
                '$runsPerModel ${runsPerModel == 1 ? 'run' : 'runs'} per model',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (modelNames.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  modelNames.join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
              if (!_selectionMode) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _openSession(sessionId),
                    icon: const Icon(Icons.chevron_right_rounded),
                    label: const Text('View session'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComparisonAction() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _selectedIds.length == 2 ? _openComparison : null,
            icon: const Icon(Icons.compare_arrows_rounded),
            label: Text('Compare (${_selectedIds.length}/2)'),
          ),
        ),
      ),
    );
  }
}
