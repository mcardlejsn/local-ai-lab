import 'package:flutter/material.dart';

import '../models/benchmark_session.dart';
import '../services/database_service.dart';

/// Side-by-side comparison of two saved benchmark sessions. Models are paired
/// by their stored model id, not their display name, so Gemini Nano still lines
/// up across sessions recorded under different AICore builds.
///
/// Read-only: nothing here runs inference or edits saved data.
class BenchmarkComparisonScreen extends StatefulWidget {
  const BenchmarkComparisonScreen({
    super.key,
    required this.sessionIdA,
    required this.sessionIdB,
  });

  final int sessionIdA;
  final int sessionIdB;

  @override
  State<BenchmarkComparisonScreen> createState() =>
      _BenchmarkComparisonScreenState();
}

/// One session's loaded state, already reduced to what the comparison needs.
class _ComparisonSide {
  const _ComparisonSide({
    required this.completedAt,
    required this.passage,
    required this.instruction,
    required this.runsPerModel,
    required this.aggregates,
  });

  final DateTime? completedAt;
  final String passage;
  final String instruction;
  final int runsPerModel;
  final List<BenchmarkAggregate> aggregates;
}

/// A model present in one or both sessions.
class _ComparisonRow {
  const _ComparisonRow({required this.earlier, required this.later});

  final BenchmarkAggregate? earlier;
  final BenchmarkAggregate? later;

  bool get isPaired => earlier != null && later != null;

  String get displayName {
    final earlierName = earlier?.modelName;
    final laterName = later?.modelName;
    if (earlierName != null && laterName != null && earlierName != laterName) {
      return laterName;
    }
    return laterName ?? earlierName ?? 'Unknown model';
  }

  /// Set when the same model id was recorded under two different names, which
  /// is how an AICore build change shows up.
  String? get renamedFrom {
    final earlierName = earlier?.modelName;
    final laterName = later?.modelName;
    if (earlierName == null || laterName == null) return null;
    return earlierName == laterName ? null : earlierName;
  }
}

class _BenchmarkComparisonScreenState extends State<BenchmarkComparisonScreen> {
  static const Color _bgColor = Color(0xFF121212);
  static const Color _surfaceColor = Color(0xFF1E1E1E);
  static const Color _accentBlue = Color(0xFF90CAF9);
  static const Color _goodGreen = Color(0xFF81C784);

  bool _isLoading = true;
  String? _errorMessage;

  _ComparisonSide? _earlier;
  _ComparisonSide? _later;
  List<_ComparisonRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<_ComparisonSide?> _loadSide(int sessionId) async {
    final saved =
        await DatabaseService.instance.getCompletedBenchmarkById(sessionId);
    if (saved == null) return null;

    final runMaps = (saved['runs'] as List).cast<Map<String, Object?>>();
    final rawCompletedAt = saved['completed_at'];

    return _ComparisonSide(
      completedAt: rawCompletedAt is String
          ? DateTime.tryParse(rawCompletedAt)?.toLocal()
          : null,
      passage: saved['passage'] as String? ?? '',
      instruction: saved['instruction'] as String? ?? '',
      runsPerModel: saved['runs_per_model'] as int? ?? 0,
      aggregates: buildAggregatesFromSavedRuns(runMaps),
    );
  }

  Future<void> _loadSessions() async {
    try {
      final first = await _loadSide(widget.sessionIdA);
      final second = await _loadSide(widget.sessionIdB);

      if (!mounted) return;

      if (first == null || second == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'One of those saved sessions could not be found.';
        });
        return;
      }

      // Order by completion time so a delta always reads as the change from the
      // older session to the newer one.
      final bool firstIsEarlier = _isEarlier(first, second);
      final earlier = firstIsEarlier ? first : second;
      final later = firstIsEarlier ? second : first;

      setState(() {
        _earlier = earlier;
        _later = later;
        _rows = _buildRows(earlier, later);
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load those sessions: $e';
      });
    }
  }

  bool _isEarlier(_ComparisonSide first, _ComparisonSide second) {
    final a = first.completedAt;
    final b = second.completedAt;
    if (a == null || b == null) return true;
    return !a.isAfter(b);
  }

  List<_ComparisonRow> _buildRows(
    _ComparisonSide earlier,
    _ComparisonSide later,
  ) {
    final earlierById = {
      for (final agg in earlier.aggregates) agg.modelId: agg,
    };
    final laterById = {
      for (final agg in later.aggregates) agg.modelId: agg,
    };

    final rows = <_ComparisonRow>[];

    // Newer session's order first, so the most recent run reads top to bottom
    // the way it does on its own detail screen.
    for (final agg in later.aggregates) {
      rows.add(
        _ComparisonRow(earlier: earlierById[agg.modelId], later: agg),
      );
    }
    for (final agg in earlier.aggregates) {
      if (!laterById.containsKey(agg.modelId)) {
        rows.add(_ComparisonRow(earlier: agg, later: null));
      }
    }

    return rows;
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
          'Compare Sessions',
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

    final earlier = _earlier!;
    final later = _later!;
    final bool samePassage = earlier.passage.trim() == later.passage.trim();
    final bool sameInstruction =
        earlier.instruction.trim() == later.instruction.trim();

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        _buildSessionHeader(earlier, later),
        if (!samePassage || !sameInstruction) ...[
          const SizedBox(height: 12),
          _buildMismatchBanner(samePassage, sameInstruction),
        ],
        const SizedBox(height: 16),
        const Text(
          'Per-model change:',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 8),
        if (_rows.isEmpty)
          const Text(
            'Neither session has any saved run records.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          )
        else
          ..._rows.map(_buildModelCard),
        const SizedBox(height: 12),
        const Text(
          'Models are matched across sessions by their stored model id, so a '
          'renamed engine build still pairs. Δ is the newer session minus the '
          'older one; green is the better direction for that metric. An '
          'accuracy of -- means no run on that side has been scored.',
          style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildSessionHeader(_ComparisonSide earlier, _ComparisonSide later) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderLine('Older', earlier),
          const SizedBox(height: 8),
          _buildHeaderLine('Newer', later),
        ],
      ),
    );
  }

  Widget _buildHeaderLine(String label, _ComparisonSide side) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(
              color: _accentBlue,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                side.completedAt == null
                    ? 'Completed date unknown'
                    : formatBenchmarkDateTime(side.completedAt!),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${side.aggregates.length} '
                'model${side.aggregates.length == 1 ? '' : 's'} · '
                '${side.runsPerModel} '
                'run${side.runsPerModel == 1 ? '' : 's'} per model',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMismatchBanner(bool samePassage, bool sameInstruction) {
    final differences = <String>[
      if (!samePassage) 'passage',
      if (!sameInstruction) 'instruction',
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1F0A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orangeAccent),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Colors.orangeAccent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'These sessions used a different ${differences.join(' and ')}. '
              'The models were not given the same task, so the differences '
              'below are not a like-for-like comparison.',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelCard(_ComparisonRow row) {
    final renamedFrom = row.renamedFrom;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          if (renamedFrom != null) ...[
            const SizedBox(height: 2),
            Text(
              'Older session recorded this as $renamedFrom',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
          if (!row.isPaired) ...[
            const SizedBox(height: 6),
            Text(
              row.later == null
                  ? 'Only in the older session — no comparison available.'
                  : 'Only in the newer session — no comparison available.',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          _buildMetricRow(
            label: 'Est. tok/s',
            earlierValue: row.earlier?.medianTokensPerSecond,
            laterValue: row.later?.medianTokensPerSecond,
            fractionDigits: 1,
            higherIsBetter: true,
          ),
          _buildMetricRow(
            label: 'TTFT (s)',
            earlierValue: row.earlier?.medianTtftSeconds,
            laterValue: row.later?.medianTtftSeconds,
            fractionDigits: 2,
            higherIsBetter: false,
          ),
          _buildMetricRow(
            label: 'Latency (s)',
            earlierValue: row.earlier?.medianLatencySeconds,
            laterValue: row.later?.medianLatencySeconds,
            fractionDigits: 2,
            higherIsBetter: false,
          ),
          _buildMetricRow(
            label: 'Est. tokens',
            earlierValue: row.earlier?.medianTokenCount?.toDouble(),
            laterValue: row.later?.medianTokenCount?.toDouble(),
            fractionDigits: 0,
            higherIsBetter: null,
          ),
          _buildMetricRow(
            label: 'Accuracy',
            earlierValue: row.earlier?.medianAccuracyScore,
            laterValue: row.later?.medianAccuracyScore,
            fractionDigits: 1,
            higherIsBetter: true,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow({
    required String label,
    required double? earlierValue,
    required double? laterValue,
    required int fractionDigits,
    required bool? higherIsBetter,
  }) {
    final bool hasDelta = earlierValue != null && laterValue != null;
    final double? delta = hasDelta ? laterValue - earlierValue : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              earlierValue?.toStringAsFixed(fractionDigits) ?? '--',
              maxLines: 1,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          const Icon(
            Icons.arrow_right_alt_rounded,
            color: Colors.white24,
            size: 16,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              laterValue?.toStringAsFixed(fractionDigits) ?? '--',
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 74,
            child: Text(
              delta == null
                  ? ''
                  : '${delta > 0 ? '+' : ''}'
                      '${delta.toStringAsFixed(fractionDigits)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: _deltaColor(delta, higherIsBetter),
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _deltaColor(double? delta, bool? higherIsBetter) {
    if (delta == null || delta == 0 || higherIsBetter == null) {
      return Colors.white38;
    }
    final bool improved = higherIsBetter ? delta > 0 : delta < 0;
    return improved ? _goodGreen : Colors.redAccent;
  }
}