import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/summary_record.dart';
import '../services/database_service.dart';

typedef SummaryHistoryLoader = Future<List<SummaryRecord>> Function();

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    this.embedded = false,
    this.recordsLoader,
    this.summaryChanges,
  });

  /// Omits the standalone scaffold when shown inside the Results screen.
  final bool embedded;

  /// Optional platform-free dependencies for focused widget tests.
  final SummaryHistoryLoader? recordsLoader;
  final ValueListenable<int>? summaryChanges;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final SummaryHistoryLoader _recordsLoader;
  late final ValueListenable<int> _summaryChanges;
  List<SummaryRecord> _records = <SummaryRecord>[];
  List<SummaryRecord> _filteredRecords = <SummaryRecord>[];
  String _selectedFilter = 'All';
  bool _isLoading = true;
  int _loadGeneration = 0;

  static const List<String> _filters = <String>[
    'All',
    '2-Sentence Summary',
    'Key Events',
    'Action Items',
    'Custom',
  ];

  @override
  void initState() {
    super.initState();
    _recordsLoader =
        widget.recordsLoader ?? DatabaseService.instance.getAllSummaries;
    _summaryChanges =
        widget.summaryChanges ?? DatabaseService.instance.summaryChanges;
    _searchController.addListener(_applyFilters);
    _summaryChanges.addListener(_onSummaryChanged);
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    _summaryChanges.removeListener(_onSummaryChanged);
    _searchController
      ..removeListener(_applyFilters)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final int generation = ++_loadGeneration;
    setState(() => _isLoading = true);
    final List<SummaryRecord> data = await _recordsLoader();
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _records = data;
      _isLoading = false;
    });
    _applyFilters();
  }

  void _onSummaryChanged() {
    unawaited(_loadHistory());
  }

  void _applyFilters() {
    if (!mounted) return;
    final String query = _searchController.text.toLowerCase().trim();
    setState(() {
      _filteredRecords = _records
          .where((SummaryRecord record) {
            final bool matchesFilter =
                _selectedFilter == 'All' || record.taskType == _selectedFilter;
            final bool matchesQuery =
                query.isEmpty ||
                record.generatedSummary.toLowerCase().contains(query) ||
                record.originalText.toLowerCase().contains(query) ||
                record.taskType.toLowerCase().contains(query) ||
                (record.modelName?.toLowerCase().contains(query) ?? false) ||
                (record.engineType?.toLowerCase().contains(query) ?? false);
            return matchesFilter && matchesQuery;
          })
          .toList(growable: false);
    });
  }

  Future<void> _deleteRecord(int id) async {
    await DatabaseService.instance.deleteSummary(id);
    _showSnackBar('Record removed.');
  }

  void _showSnackBar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _showFullOutput(SummaryRecord record) {
    final ThemeData theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      builder: (BuildContext sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (BuildContext context, ScrollController scrollController) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Saved run',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded),
                      tooltip: 'Copy full output',
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: record.generatedSummary),
                        );
                        _showSnackBar('Copied to clipboard.');
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    Text(
                      record.taskType,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (record.sentenceCountMet != null) ...[
                      const SizedBox(height: 12),
                      _buildSentenceCountBadge(record),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      record.generatedSummary,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Original passage',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      record.originalText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasSavedRecords = _records.isNotEmpty;
    final Widget content = Column(
      children: [
        if (hasSavedRecords) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const Key('results-playground-search'),
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search models, tasks, or text',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: DropdownMenu<String>(
              key: const Key('results-playground-task-filter'),
              initialSelection: _selectedFilter,
              expandedInsets: EdgeInsets.zero,
              label: const Text('Task filter'),
              dropdownMenuEntries: [
                for (final String filter in _filters)
                  DropdownMenuEntry<String>(value: filter, label: filter),
              ],
              onSelected: (String? filter) {
                if (filter == null || filter == _selectedFilter) return;
                setState(() => _selectedFilter = filter);
                _applyFilters();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Saved runs',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_filteredRecords.length} saved '
                    '${_filteredRecords.length == 1 ? 'run' : 'runs'}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        Expanded(child: _buildRecordList()),
      ],
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Saved runs')),
      body: SafeArea(child: content),
    );
  }

  Widget _buildRecordList() {
    final ThemeData theme = Theme.of(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_filteredRecords.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _records.isEmpty
                    ? Icons.bookmark_border_rounded
                    : Icons.search_off_rounded,
                color: theme.colorScheme.onSurfaceVariant,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                _records.isEmpty
                    ? 'No saved runs yet.'
                    : 'No saved runs match these filters.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                _records.isEmpty
                    ? 'After generating an output in Run, tap Save to '
                          'keep its output and telemetry here.'
                    : 'Try another task filter or search term.',
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

    return ListView.builder(
      key: const PageStorageKey<String>('playground-results-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: _filteredRecords.length,
      itemBuilder: (BuildContext context, int index) =>
          _buildRecordCard(_filteredRecords[index]),
    );
  }

  Widget _buildRecordCard(SummaryRecord record) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String model = record.modelName ?? 'Unknown model';

    return Card(
      key: PageStorageKey<String>('history_tile_${record.id}'),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${record.taskType} · $model',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _formatDate(record.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${_engineLabel(record.engineType)} · Completed locally',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            if (record.sentenceCountMet != null) ...[
              const SizedBox(height: 10),
              _buildSentenceCountBadge(record),
            ],
            const SizedBox(height: 16),
            Text(
              record.generatedSummary,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
            ),
            if (record.latencySeconds != null ||
                record.ttftSeconds != null ||
                record.tokensPerSecond != null ||
                record.tokenCount != null) ...[
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 14),
              Wrap(
                spacing: 28,
                runSpacing: 16,
                children: [
                  _buildMetric(
                    'LATENCY',
                    record.latencySeconds == null
                        ? '--'
                        : '${record.latencySeconds!.toStringAsFixed(2)}s',
                  ),
                  _buildMetric(
                    'TTFT',
                    record.ttftSeconds == null
                        ? '--'
                        : '${record.ttftSeconds!.toStringAsFixed(2)}s',
                  ),
                  _buildMetric(
                    'RATE',
                    record.tokensPerSecond == null
                        ? '--'
                        : '${record.tokensPerSecond!.toStringAsFixed(1)} est. tok/s',
                  ),
                  _buildMetric('TOKENS', record.tokenCount?.toString() ?? '--'),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => _showFullOutput(record),
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('View run'),
                ),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: record.generatedSummary),
                    );
                    _showSnackBar('Copied to clipboard.');
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy'),
                ),
                if (record.id != null)
                  TextButton.icon(
                    onPressed: () => _deleteRecord(record.id!),
                    style: TextButton.styleFrom(foregroundColor: colors.error),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSentenceCountBadge(SummaryRecord record) {
    final ThemeData theme = Theme.of(context);
    final bool met = record.sentenceCountMet == true;
    final Color color = met
        ? (theme.brightness == Brightness.dark
              ? const Color(0xFF81C784)
              : const Color(0xFF2E7D32))
        : theme.colorScheme.tertiary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(31),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            met
                ? Icons.check_circle_outline_rounded
                : Icons.warning_amber_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              '${met ? 'Length met' : 'Length not met'} · '
              '${record.actualSentenceCount}/${record.expectedSentenceCount} sentences',
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value) {
    final ThemeData theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 76, maxWidth: 150),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }

  String _engineLabel(String? engine) {
    return switch (engine?.toLowerCase()) {
      'nano' => 'AICore',
      'gguf' => 'GGUF',
      'litertlm' => 'LiteRT-LM',
      'mediapipe' => 'Legacy',
      final String value when value.isNotEmpty => value,
      _ => 'Local runtime',
    };
  }

  String _formatDate(DateTime dateTime) {
    final DateTime local = dateTime.toLocal();
    final int hour = local.hour == 0
        ? 12
        : local.hour > 12
        ? local.hour - 12
        : local.hour;
    final String minute = local.minute.toString().padLeft(2, '0');
    final String period = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.month}/${local.day}/${local.year}\n$hour:$minute $period';
  }
}
