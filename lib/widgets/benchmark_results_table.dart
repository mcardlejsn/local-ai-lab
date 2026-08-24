import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/benchmark_session.dart';
import '../models/recall_checklist.dart';
import '../services/model_manager_service.dart';

/// Signature for persisting a manual accuracy score. [score] and [note] are
/// written as given, so nulls clear the existing values.
typedef BenchmarkRunScoreCallback = Future<void> Function(
  BenchmarkModelResult run,
  int? score,
  String? note,
);

/// The comparison table for a set of benchmark aggregates, plus the per-model
/// output modal and the methodology footnote. Shared by the live benchmark
/// screen and the read-only saved-session detail screen so both render results
/// identically.
///
/// Scoring is optional: pass [onScoreRun] to make the runs in the output modal
/// scorable. With it omitted, scores are shown but cannot be edited, which is
/// what the live benchmark screen uses since its runs are not saved yet.
class BenchmarkResultsTable extends StatelessWidget {
  const BenchmarkResultsTable({
    super.key,
    required this.aggregates,
    this.showFootnote = true,
    this.showAccuracy = true,
    this.onScoreRun,
  });

  final List<BenchmarkAggregate> aggregates;
  final bool showFootnote;

  /// Whether to show the manual accuracy column. The live benchmark screen
  /// hides it: scoring is a sit-down-and-read-the-output job, done from the
  /// archive. Automatic recall shows on both.
  final bool showAccuracy;

  final BenchmarkRunScoreCallback? onScoreRun;

  static const Color _surfaceColor = Color(0xFF1E1E1E);
  static const Color _accentBlue = Color(0xFF90CAF9);

  void _showOutputModal(BuildContext context, BenchmarkAggregate item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surfaceColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (_, controller) {
            return _OutputModalContent(
              item: item,
              scrollController: controller,
              onScoreRun: onScoreRun,
              hostContext: context,
              sheetContext: ctx,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: _surfaceColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.black26),
              dataRowMinHeight: 48,
              dataRowMaxHeight: 64,
              columns: [
                const DataColumn(
                  label: Text(
                    'Model / Engine',
                    style: TextStyle(
                        color: _accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
                const DataColumn(
                  label: Text(
                    'Runs',
                    style: TextStyle(
                        color: _accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
                const DataColumn(
                  label: Text(
                    'Est. tok/s (chars÷4)',
                    style: TextStyle(
                        color: _accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
                const DataColumn(
                  label: Text(
                    'TTFT (s)',
                    style: TextStyle(
                        color: _accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
                const DataColumn(
                  label: Text(
                    'Latency (s)',
                    style: TextStyle(
                        color: _accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
                const DataColumn(
                  label: Text(
                    'Est. tokens',
                    style: TextStyle(
                        color: _accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
                const DataColumn(
                  label: Text(
                    'Recall',
                    style: TextStyle(
                        color: _accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
                if (showAccuracy)
                  const DataColumn(
                    label: Text(
                      'Accuracy',
                      style: TextStyle(
                          color: _accentBlue, fontWeight: FontWeight.bold),
                    ),
                  ),
                const DataColumn(
                  label: Text(
                    'Output',
                    style: TextStyle(
                        color: _accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              rows: aggregates.map((agg) {
                final bool hasResults = agg.hasAnySuccess;
                final double? medianSpeed = agg.medianTokensPerSecond;
                final double? medianTtft = agg.medianTtftSeconds;
                final double? medianLatency = agg.medianLatencySeconds;
                final double? minLatency = agg.minLatencySeconds;
                final double? maxLatency = agg.maxLatencySeconds;
                final int? medianTokens = agg.medianTokenCount;
                final int successCount = agg.successfulRuns.length;
                final double? medianScore = agg.medianAccuracyScore;

                final double? medianRecall = agg.medianRecallFound;
                final int? recallTotal = agg.recallTotal;

                return DataRow(
                  cells: [
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          agg.modelName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        '$successCount/${agg.runs.length}',
                        style: TextStyle(
                          color: successCount == agg.runs.length
                              ? Colors.white70
                              : Colors.orangeAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        medianSpeed != null
                            ? medianSpeed.toStringAsFixed(1)
                            : 'ERR',
                        style: TextStyle(
                          color: hasResults
                              ? const Color(0xFF81C784)
                              : Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        agg.engine == ModelEngine.nano
                            ? (medianLatency != null
                                ? '${medianLatency.toStringAsFixed(2)}s*'
                                : '--')
                            : (medianTtft != null
                                ? '${medianTtft.toStringAsFixed(2)}s'
                                : '--'),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                    DataCell(
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            medianLatency != null
                                ? '${medianLatency.toStringAsFixed(2)}s'
                                : '--',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          if (successCount > 1 &&
                              minLatency != null &&
                              maxLatency != null)
                            Text(
                              '${minLatency.toStringAsFixed(2)}–${maxLatency.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ),
                    DataCell(
                      Text(
                        medianTokens?.toString() ?? '--',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                    DataCell(
                      medianRecall != null && recallTotal != null
                          ? Text(
                              '${formatAccuracyScore(medianRecall)}'
                              '/$recallTotal',
                              style: TextStyle(
                                color: recallColor(medianRecall, recallTotal),
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : const Text(
                              'Not graded',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 11),
                            ),
                    ),
                    if (showAccuracy)
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              medianScore != null
                                  ? formatAccuracyScore(medianScore)
                                  : 'Unscored',
                              style: TextStyle(
                                color: medianScore != null
                                    ? accuracyScoreColor(medianScore)
                                    : Colors.white38,
                                fontWeight: medianScore != null
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: medianScore != null ? 14 : 11,
                              ),
                            ),
                            if (medianScore != null &&
                                agg.scoredRunCount < successCount)
                              Text(
                                '${agg.scoredRunCount}/$successCount scored',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                          ],
                        ),
                      ),
                    DataCell(
                      IconButton(
                        icon: const Icon(
                          Icons.visibility_rounded,
                          size: 18,
                          color: _accentBlue,
                        ),
                        onPressed: agg.runs.isEmpty
                            ? null
                            : () => _showOutputModal(context, agg),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
        if (showFootnote) ...[
          const SizedBox(height: 10),
          const Text(
            'Timings are the median across the runs completed for each model; the '
            'smaller figure under latency is the min–max range across those runs.\n'
            'Token counts are estimated as output characters ÷ 4, not tokenizer '
            'output. Each engine uses a different tokenizer, and the rate uses '
            'total latency including prompt processing and TTFT. It is therefore '
            'an end-to-end throughput proxy, not pure decode speed.\n'
            'Recall is graded automatically: the share of the passage\'s '
            'expected facts that appear in the output, median across runs. It '
            'counts what was kept and cannot see what was invented.\n'
            'Accuracy is a manual 0–5 score assigned per run against the source '
            'passage; the column shows the median across scored runs. It is a '
            'judgement, not a measurement.\n'
            '* Gemini Nano\'s Prompt API is non-streaming — time to first token '
            'cannot be measured, so total latency is shown in that column.',
            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
          ),
        ],
      ],
    );
  }
}

/// Renders a score as a whole number when it lands on one, so a single scored
/// run reads as `4` rather than `4.0`.
String formatAccuracyScore(double score) {
  return score == score.roundToDouble()
      ? score.round().toString()
      : score.toStringAsFixed(1);
}

/// Colors recall by how much of the checklist survived.
Color recallColor(double found, int total) {
  if (total == 0) return Colors.white38;
  final fraction = found / total;
  if (fraction >= 0.9) return const Color(0xFF81C784);
  if (fraction >= 0.6) return Colors.orangeAccent;
  return Colors.redAccent;
}

Color accuracyScoreColor(double score) {
  if (score >= 4) return const Color(0xFF81C784);
  if (score >= 2) return Colors.orangeAccent;
  return Colors.redAccent;
}

/// The body of the per-model output modal. Stateful so a score entered while
/// the sheet is open is reflected immediately without waiting for the host
/// screen to reload the session.
class _OutputModalContent extends StatefulWidget {
  const _OutputModalContent({
    required this.item,
    required this.scrollController,
    required this.onScoreRun,
    required this.hostContext,
    required this.sheetContext,
  });

  final BenchmarkAggregate item;
  final ScrollController scrollController;
  final BenchmarkRunScoreCallback? onScoreRun;

  /// Context of the screen hosting the table, used for snackbars that should
  /// outlive the sheet.
  final BuildContext hostContext;

  /// Context of the sheet itself, used to dismiss it.
  final BuildContext sheetContext;

  @override
  State<_OutputModalContent> createState() => _OutputModalContentState();
}

class _OutputModalContentState extends State<_OutputModalContent> {
  static const Color _accentBlue = Color(0xFF90CAF9);

  late List<BenchmarkModelResult> _runs;

  @override
  void initState() {
    super.initState();
    _runs = List<BenchmarkModelResult>.from(widget.item.runs);
  }

  BenchmarkModelResult? get _representative {
    final successful = _runs.where((r) => r.errorMessage == null).toList();
    if (successful.isEmpty) return null;
    final sorted = [...successful]
      ..sort((a, b) => a.totalLatencySeconds.compareTo(b.totalLatencySeconds));
    return sorted[(sorted.length - 1) ~/ 2];
  }

  bool get _canScore => widget.onScoreRun != null;

  Future<void> _editScore(int index) async {
    final callback = widget.onScoreRun;
    final run = _runs[index];
    if (callback == null || !run.isScorable) return;

    final result = await showDialog<_ScoreDialogResult>(
      context: context,
      builder: (_) => _ScoreDialog(
        runNumber: index + 1,
        modelName: widget.item.modelName,
        initialScore: run.accuracyScore,
        initialNote: run.scoreNote,
      ),
    );

    if (result == null) return;

    await callback(run, result.score, result.note);
    if (!mounted) return;

    setState(() {
      _runs[index] = run.copyWithScore(result.score, result.note);
    });
  }

  @override
  Widget build(BuildContext context) {
    final representative = _representative;
    final String outputText = representative?.outputText ?? '';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        controller: widget.scrollController,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.item.modelName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded,
                    color: _accentBlue, size: 20),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: outputText));
                  Navigator.pop(widget.sheetContext);
                  ScaffoldMessenger.of(widget.hostContext).showSnackBar(
                    const SnackBar(
                        content: Text('Copied output to clipboard.')),
                  );
                },
              ),
            ],
          ),
          const Divider(color: Colors.white12),
          const SizedBox(height: 4),
          Text(
            _canScore
                ? 'Per-run latency (tap a run to score):'
                : 'Per-run latency:',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          ...List.generate(_runs.length, (index) {
            final run = _runs[index];
            final bool failed = run.errorMessage != null;
            final bool tappable = _canScore && !failed && run.isScorable;

            final line = failed
                ? 'Run ${index + 1}: failed — ${run.errorMessage}'
                : 'Run ${index + 1}: ${run.totalLatencySeconds.toStringAsFixed(2)}s'
                    ' · ${run.tokensPerSecond.toStringAsFixed(1)} est. tok/s'
                    ' · ${run.tokenCount} est. tokens';

            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        line,
                        style: TextStyle(
                          color: failed ? Colors.redAccent : Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (!failed)
                      Text(
                        run.isScored
                            ? 'Accuracy ${run.accuracyScore}/5'
                            : (tappable ? 'Score' : 'Unscored'),
                        style: TextStyle(
                          color: run.isScored
                              ? accuracyScoreColor(
                                  run.accuracyScore!.toDouble())
                              : (tappable ? _accentBlue : Colors.white38),
                          fontSize: 12,
                          fontWeight: run.isScored
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                  ],
                ),
                if (!failed && run.isRecallGraded)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      run.missedFactIds.isEmpty
                          ? 'Recall ${run.recallFound}/${run.recallTotal} — '
                              'nothing dropped'
                          : 'Recall ${run.recallFound}/${run.recallTotal} — '
                              'dropped ${_describeMissedFacts(run.missedFactIds)}',
                      style: TextStyle(
                        color: run.missedFactIds.isEmpty
                            ? Colors.white38
                            : Colors.orangeAccent,
                        fontSize: 11,
                      ),
                    ),
                  ),
                if (!failed && (run.scoreNote?.trim().isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      run.scoreNote!.trim(),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            );

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: tappable
                  ? InkWell(
                      onTap: () => _editScore(index),
                      child: content,
                    )
                  : content,
            );
          }),
          const SizedBox(height: 12),
          const Text(
            'Output (median-latency run):',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            outputText.isEmpty ? '(No output generated)' : outputText,
            style: const TextStyle(
                color: Colors.white70, fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Turns stored fact ids into the checklist's human-readable labels, falling
/// back to the raw id if a stored run references a fact the checklist no
/// longer has.
String _describeMissedFacts(List<String> ids) {
  final checklist = benchmarkPassage.checklist;
  return ids
      .map((id) => checklist.factById(id)?.label ?? id)
      .join('; ');
}

class _ScoreDialogResult {
  const _ScoreDialogResult(this.score, this.note);

  final int? score;
  final String? note;
}

/// Score picker for a single run: a 0–5 scale plus an optional note recording
/// what the output got wrong.
class _ScoreDialog extends StatefulWidget {
  const _ScoreDialog({
    required this.runNumber,
    required this.modelName,
    required this.initialScore,
    required this.initialNote,
  });

  final int runNumber;
  final String modelName;
  final int? initialScore;
  final String? initialNote;

  @override
  State<_ScoreDialog> createState() => _ScoreDialogState();
}

class _ScoreDialogState extends State<_ScoreDialog> {
  static const Color _surfaceColor = Color(0xFF1E1E1E);
  static const Color _accentBlue = Color(0xFF90CAF9);

  late int? _score = widget.initialScore;
  late final TextEditingController _noteController =
      TextEditingController(text: widget.initialNote ?? '');

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _surfaceColor,
      title: Text(
        'Score run ${widget.runNumber}',
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.modelName,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text(
              '5 = faithful and complete · 3 = usable with omissions · '
              '0 = fabricated or unusable',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: List.generate(6, (value) {
                final bool selected = _score == value;
                return ChoiceChip(
                  label: Text('$value'),
                  selected: selected,
                  onSelected: (_) => setState(() => _score = value),
                  backgroundColor: Colors.black26,
                  selectedColor: _accentBlue,
                  labelStyle: TextStyle(
                    color: selected ? Colors.black : Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                labelStyle: TextStyle(color: Colors.white54),
                hintText: 'e.g. invented the clinic, dropped both medications',
                hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: _accentBlue),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            const _ScoreDialogResult(null, null),
          ),
          child: const Text('Clear',
              style: TextStyle(color: Colors.orangeAccent)),
        ),
        TextButton(
          onPressed: _score == null
              ? null
              : () {
                  final note = _noteController.text.trim();
                  Navigator.pop(
                    context,
                    _ScoreDialogResult(_score, note.isEmpty ? null : note),
                  );
                },
          child: const Text('Save', style: TextStyle(color: _accentBlue)),
        ),
      ],
    );
  }
}