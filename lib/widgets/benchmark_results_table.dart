import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/benchmark_session.dart';
import '../presentation/model_identity_presentation.dart';
import '../services/model_manager_service.dart';

typedef BenchmarkRunScoreCallback =
    Future<void> Function(BenchmarkModelResult run, int? score, String? note);

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
  final bool showAccuracy;
  final BenchmarkRunScoreCallback? onScoreRun;

  void _showOutputModal(
    BuildContext context,
    BenchmarkAggregate item,
    String displayName,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (BuildContext sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.68,
          maxChildSize: 0.92,
          minChildSize: 0.42,
          builder: (_, ScrollController controller) {
            return _OutputModalContent(
              item: item,
              displayName: displayName,
              scrollController: controller,
              onScoreRun: onScoreRun,
              hostContext: context,
              sheetContext: sheetContext,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<String, String> displayNames = resolveConciseModelNames(
      aggregates.map(
        (BenchmarkAggregate aggregate) => ModelDisplayIdentity(
          key: aggregate.modelId,
          technicalName: aggregate.modelName,
          engine: aggregate.engine,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int index = 0; index < aggregates.length; index++) ...[
          _BenchmarkResultCard(
            key: Key('benchmark-result-${aggregates[index].modelId}'),
            aggregate: aggregates[index],
            displayName: displayNames[aggregates[index].modelId]!,
            showAccuracy: showAccuracy,
            onViewOutput: aggregates[index].runs.isEmpty
                ? null
                : () => _showOutputModal(
                    context,
                    aggregates[index],
                    displayNames[aggregates[index].modelId]!,
                  ),
          ),
          if (index != aggregates.length - 1) const SizedBox(height: 12),
        ],
        if (showFootnote) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            key: const Key('benchmark-methodology'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            title: Text(
              'How metrics are calculated',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            children: [
              Text(
                'Timings are medians across completed runs. Latency also shows '
                'the min–max range when multiple runs succeed.\n\n'
                'Token counts estimate output characters ÷ 4. Rate is estimated '
                'tokens divided by total latency, including prompt processing '
                'and TTFT, so it is an end-to-end proxy rather than pure decode '
                'speed.\n\n'
                'Recall measures how many expected content words remain in the '
                'output. Accuracy is a manual 0–5 review score available in '
                'saved-session details.\n\n'
                'Gemini Nano is non-streaming, so its TTFT cannot be measured '
                'separately.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _BenchmarkResultCard extends StatelessWidget {
  const _BenchmarkResultCard({
    super.key,
    required this.aggregate,
    required this.displayName,
    required this.showAccuracy,
    required this.onViewOutput,
  });

  final BenchmarkAggregate aggregate;
  final String displayName;
  final bool showAccuracy;
  final VoidCallback? onViewOutput;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final int successCount = aggregate.successfulRuns.length;
    final bool allSucceeded =
        aggregate.runs.isNotEmpty && successCount == aggregate.runs.length;
    final bool hasResults = aggregate.hasAnySuccess;

    final double? medianSpeed = aggregate.medianTokensPerSecond;
    final double? medianTtft = aggregate.medianTtftSeconds;
    final double? medianLatency = aggregate.medianLatencySeconds;
    final double? minLatency = aggregate.minLatencySeconds;
    final double? maxLatency = aggregate.maxLatencySeconds;
    final int? medianTokens = aggregate.medianTokenCount;
    final double? medianRecall = aggregate.medianRecallFound;
    final int? recallTotal = aggregate.recallTotal;
    final double? medianScore = aggregate.medianAccuracyScore;
    final int sentenceCountRunCount = aggregate.sentenceCountRuns.length;

    final String latencyDetail =
        successCount > 1 && minLatency != null && maxLatency != null
        ? '${minLatency.toStringAsFixed(2)}–'
              '${maxLatency.toStringAsFixed(2)}s range'
        : 'median';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            key: Key('benchmark-result-header-${aggregate.modelId}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ModelRuntimeBadge(
                key: Key('benchmark-result-runtime-${aggregate.modelId}'),
                engine: aggregate.engine,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                allSucceeded
                    ? Icons.check_circle_outline_rounded
                    : hasResults
                    ? Icons.warning_amber_rounded
                    : Icons.error_outline_rounded,
                size: 18,
                color: allSucceeded
                    ? const Color(0xFF4F9D69)
                    : hasResults
                    ? colors.tertiary
                    : colors.error,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$successCount of ${aggregate.runs.length} runs completed',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double itemWidth = constraints.maxWidth >= 520
                  ? (constraints.maxWidth - 24) / 3
                  : (constraints.maxWidth - 12) / 2;

              final List<Widget> metrics = [
                _MetricTile(
                  width: itemWidth,
                  label: 'RATE',
                  value: medianSpeed?.toStringAsFixed(1) ?? '--',
                  detail: medianSpeed == null ? null : 'est. tok/s',
                ),
                _MetricTile(
                  width: itemWidth,
                  label: 'TTFT',
                  value: aggregate.engine == ModelEngine.nano
                      ? '--'
                      : medianTtft == null
                      ? '--'
                      : '${medianTtft.toStringAsFixed(2)}s',
                  detail: aggregate.engine == ModelEngine.nano
                      ? 'non-streaming'
                      : 'median',
                ),
                _MetricTile(
                  width: itemWidth,
                  label: 'LATENCY',
                  value: medianLatency == null
                      ? '--'
                      : '${medianLatency.toStringAsFixed(2)}s',
                  detail: medianLatency == null ? null : latencyDetail,
                ),
                _MetricTile(
                  width: itemWidth,
                  label: 'EST. TOKENS',
                  value: medianTokens?.toString() ?? '--',
                  detail: 'chars ÷ 4',
                ),
                _MetricTile(
                  width: itemWidth,
                  label: 'RECALL',
                  value: medianRecall != null && recallTotal != null
                      ? '${formatAccuracyScore(medianRecall)}/$recallTotal'
                      : '--',
                  detail: medianRecall == null ? 'not graded' : 'median',
                  valueColor: medianRecall != null && recallTotal != null
                      ? recallColor(medianRecall, recallTotal)
                      : null,
                ),
                if (sentenceCountRunCount > 0)
                  _MetricTile(
                    width: itemWidth,
                    label: 'LENGTH MET',
                    value:
                        '${aggregate.sentenceCountMetRunCount}/$sentenceCountRunCount',
                    detail: 'runs met target',
                    valueColor:
                        aggregate.sentenceCountMetRunCount ==
                            sentenceCountRunCount
                        ? const Color(0xFF4F9D69)
                        : colors.tertiary,
                  ),
                if (showAccuracy)
                  _MetricTile(
                    width: itemWidth,
                    label: 'ACCURACY',
                    value: medianScore == null
                        ? '--'
                        : formatAccuracyScore(medianScore),
                    detail: medianScore == null
                        ? 'unscored'
                        : '${aggregate.scoredRunCount}/$successCount scored',
                    valueColor: medianScore == null
                        ? null
                        : accuracyScoreColor(medianScore),
                  ),
              ];

              return Wrap(spacing: 12, runSpacing: 14, children: metrics);
            },
          ),
          if (aggregate.firstError != null) ...[
            const SizedBox(height: 12),
            Text(
              aggregate.firstError!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onViewOutput,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('View runs and output'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.width,
    required this.label,
    required this.value,
    this.detail,
    this.valueColor,
  });

  final double width;
  final String label;
  final String value;
  final String? detail;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (detail != null)
            Text(
              detail!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

String formatAccuracyScore(double score) {
  return score == score.roundToDouble()
      ? score.round().toString()
      : score.toStringAsFixed(1);
}

Color recallColor(double found, int total) {
  if (total == 0) return Colors.grey;
  final double fraction = found / total;
  if (fraction >= 0.9) return const Color(0xFF4F9D69);
  if (fraction >= 0.6) return const Color(0xFFB26A00);
  return const Color(0xFFBA1A1A);
}

Color accuracyScoreColor(double score) {
  if (score >= 4) return const Color(0xFF4F9D69);
  if (score >= 2) return const Color(0xFFB26A00);
  return const Color(0xFFBA1A1A);
}

class _OutputModalContent extends StatefulWidget {
  const _OutputModalContent({
    required this.item,
    required this.displayName,
    required this.scrollController,
    required this.onScoreRun,
    required this.hostContext,
    required this.sheetContext,
  });

  final BenchmarkAggregate item;
  final String displayName;
  final ScrollController scrollController;
  final BenchmarkRunScoreCallback? onScoreRun;
  final BuildContext hostContext;
  final BuildContext sheetContext;

  @override
  State<_OutputModalContent> createState() => _OutputModalContentState();
}

class _OutputModalContentState extends State<_OutputModalContent> {
  late List<BenchmarkModelResult> _runs;

  @override
  void initState() {
    super.initState();
    _runs = List<BenchmarkModelResult>.from(widget.item.runs);
  }

  BenchmarkModelResult? get _representative {
    final List<BenchmarkModelResult> successful = _runs
        .where((BenchmarkModelResult run) => run.errorMessage == null)
        .toList();
    if (successful.isEmpty) return null;
    successful.sort(
      (BenchmarkModelResult a, BenchmarkModelResult b) =>
          a.totalLatencySeconds.compareTo(b.totalLatencySeconds),
    );
    return successful[(successful.length - 1) ~/ 2];
  }

  bool get _canScore => widget.onScoreRun != null;

  Future<void> _editScore(int index) async {
    final BenchmarkRunScoreCallback? callback = widget.onScoreRun;
    final BenchmarkModelResult run = _runs[index];
    if (callback == null || !run.isScorable) return;

    final _ScoreDialogResult? result = await showDialog<_ScoreDialogResult>(
      context: context,
      builder: (_) => _ScoreDialog(
        runNumber: index + 1,
        modelName: widget.displayName,
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

  void _copyOutput(String outputText) {
    Clipboard.setData(ClipboardData(text: outputText));
    Navigator.pop(widget.sheetContext);
    ScaffoldMessenger.of(widget.hostContext).showSnackBar(
      const SnackBar(content: Text('Copied output to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BenchmarkModelResult? representative = _representative;
    final String outputText = representative?.outputText ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: ListView(
        controller: widget.scrollController,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy output',
                onPressed: outputText.isEmpty
                    ? null
                    : () => _copyOutput(outputText),
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            _canScore
                ? 'Runs — tap a completed run to score'
                : 'Individual runs',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (int index = 0; index < _runs.length; index++)
            _RunSummary(
              runNumber: index + 1,
              run: _runs[index],
              canScore: _canScore && _runs[index].isScorable,
              onTap: () => _editScore(index),
            ),
          const SizedBox(height: 20),
          Text(
            'Output from the median-latency run',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            outputText.isEmpty ? '(No output generated)' : outputText,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _RunSummary extends StatelessWidget {
  const _RunSummary({
    required this.runNumber,
    required this.run,
    required this.canScore,
    required this.onTap,
  });

  final int runNumber;
  final BenchmarkModelResult run;
  final bool canScore;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool failed = run.errorMessage != null;
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            failed
                ? 'Run $runNumber failed'
                : 'Run $runNumber · '
                      '${run.totalLatencySeconds.toStringAsFixed(2)}s · '
                      '${run.tokensPerSecond.toStringAsFixed(1)} est. tok/s · '
                      '${run.tokenCount} est. tokens',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: failed
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (failed)
            Text(
              run.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          if (!failed && run.isRecallGraded)
            Text(
              run.missedFactIds.isEmpty
                  ? 'Recall ${run.recallFound}/${run.recallTotal} — nothing dropped'
                  : 'Recall ${run.recallFound}/${run.recallTotal} — dropped '
                        '${_describeMissedFacts(run.missedFactIds)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (!failed && run.hasSentenceCountRequirement)
            Text(
              run.actualSentenceCount == null
                  ? 'Length not evaluated'
                  : '${run.sentenceCountMet == true ? 'Length met' : 'Length not met'} '
                        '· ${run.actualSentenceCount}/${run.expectedSentenceCount} sentences',
              style: theme.textTheme.bodySmall?.copyWith(
                color: run.sentenceCountMet == true
                    ? const Color(0xFF4F9D69)
                    : theme.colorScheme.tertiary,
              ),
            ),
          if (!failed && run.isScored)
            Text(
              'Accuracy ${run.accuracyScore}/5'
              '${run.scoreNote?.trim().isNotEmpty == true ? ' · ${run.scoreNote!.trim()}' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: accuracyScoreColor(run.accuracyScore!.toDouble()),
              ),
            )
          else if (!failed && canScore)
            Text(
              'Tap to score',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
    );

    if (!canScore || failed) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: content,
    );
  }
}

String _describeMissedFacts(List<String> tokens) {
  const int shown = 6;
  if (tokens.length <= shown) return tokens.join(', ');
  final int rest = tokens.length - shown;
  return '${tokens.take(shown).join(', ')} +$rest more';
}

class _ScoreDialogResult {
  const _ScoreDialogResult(this.score, this.note);

  final int? score;
  final String? note;
}

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
  late int? _score = widget.initialScore;
  late final TextEditingController _noteController = TextEditingController(
    text: widget.initialNote ?? '',
  );

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      title: Text('Score run ${widget.runNumber}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.modelName,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '5 = faithful and complete · 3 = usable with omissions · '
              '0 = fabricated or unusable',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List<Widget>.generate(6, (int value) {
                return ChoiceChip(
                  label: Text('$value'),
                  selected: _score == value,
                  onSelected: (_) => setState(() => _score = value),
                );
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'What was invented, omitted, or especially strong?',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, const _ScoreDialogResult(null, null)),
          child: const Text('Clear'),
        ),
        FilledButton(
          onPressed: _score == null
              ? null
              : () {
                  final String note = _noteController.text.trim();
                  Navigator.pop(
                    context,
                    _ScoreDialogResult(_score, note.isEmpty ? null : note),
                  );
                },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
