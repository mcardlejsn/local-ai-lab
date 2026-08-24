import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/benchmark_session.dart';
import '../services/model_manager_service.dart';

/// The comparison table for a set of benchmark aggregates, plus the per-model
/// output modal and the methodology footnote. Shared by the live benchmark
/// screen and the read-only saved-session detail screen so both render results
/// identically.
class BenchmarkResultsTable extends StatelessWidget {
  const BenchmarkResultsTable({
    super.key,
    required this.aggregates,
    this.showFootnote = true,
  });

  final List<BenchmarkAggregate> aggregates;
  final bool showFootnote;

  static const Color _surfaceColor = Color(0xFF1E1E1E);
  static const Color _accentBlue = Color(0xFF90CAF9);

  void _showOutputModal(BuildContext context, BenchmarkAggregate item) {
    final representative = item.medianRun;
    final String outputText = representative?.outputText ?? '';

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
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                controller: controller,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.modelName,
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
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Copied output to clipboard.')),
                          );
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 4),
                  const Text(
                    'Per-run latency:',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...List.generate(item.runs.length, (index) {
                    final run = item.runs[index];
                    final bool failed = run.errorMessage != null;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        failed
                            ? 'Run ${index + 1}: failed — ${run.errorMessage}'
                            : 'Run ${index + 1}: ${run.totalLatencySeconds.toStringAsFixed(2)}s'
                                ' · ${run.tokensPerSecond.toStringAsFixed(1)} est. tok/s'
                                ' · ${run.tokenCount} est. tokens',
                        style: TextStyle(
                          color: failed ? Colors.redAccent : Colors.white54,
                          fontSize: 12,
                        ),
                      ),
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
              columns: const [
                DataColumn(
                  label: Text(
                    'Model / Engine',
                    style: TextStyle(
                        color: _accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Runs',
                    style: TextStyle(
                        color: _accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Est. tok/s (chars÷4)',
                    style: TextStyle(
                        color: _accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'TTFT (s)',
                    style: TextStyle(
                        color: _accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Latency (s)',
                    style: TextStyle(
                        color: _accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
                  label: Text(
                    'Est. tokens',
                    style: TextStyle(
                        color: _accentBlue, fontWeight: FontWeight.bold),
                  ),
                ),
                DataColumn(
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
            '* Gemini Nano\'s Prompt API is non-streaming — time to first token '
            'cannot be measured, so total latency is shown in that column.',
            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
          ),
        ],
      ],
    );
  }
}