import 'package:flutter/material.dart';

import 'history_screen.dart';
import 'saved_benchmark_sessions_screen.dart';
import 'settings_screen.dart';

enum _ResultsSection { playground, benchmarks }

class ResultsScreen extends StatefulWidget {
  const ResultsScreen({
    super.key,
    this.playgroundRunsBuilder,
    this.benchmarksBuilder,
  });

  /// Optional platform-free content builders for focused widget tests.
  final WidgetBuilder? playgroundRunsBuilder;
  final WidgetBuilder? benchmarksBuilder;

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  _ResultsSection _section = _ResultsSection.playground;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 82,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Results',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'Saved runs and benchmarks',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => openSettings(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<_ResultsSection>(
                  key: const Key('results-section-selector'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: _ResultsSection.playground,
                      label: Text('Runs'),
                    ),
                    ButtonSegment(
                      value: _ResultsSection.benchmarks,
                      label: Text('Benchmarks'),
                    ),
                  ],
                  selected: {_section},
                  onSelectionChanged: (Set<_ResultsSection> selected) {
                    setState(() => _section = selected.single);
                  },
                ),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _section.index,
                children: [_buildPlaygroundRuns(), _buildBenchmarks()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaygroundRuns() {
    final WidgetBuilder? builder = widget.playgroundRunsBuilder;
    if (builder != null) return builder(context);
    return const HistoryScreen(embedded: true);
  }

  Widget _buildBenchmarks() {
    final WidgetBuilder? builder = widget.benchmarksBuilder;
    if (builder != null) return builder(context);
    return const SavedBenchmarkSessionsScreen(embedded: true);
  }
}
