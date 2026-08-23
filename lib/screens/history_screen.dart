import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/summary_record.dart';
import '../services/database_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<SummaryRecord> _records = [];
  List<SummaryRecord> _filteredRecords = [];
  String _selectedFilter = 'All';
  bool _isLoading = true;

  /// Benchmark rows are saved with a 'Benchmark: <instruction>' task type, so
  /// they are matched by prefix rather than by an exact task name.
  static const String _benchmarkFilter = 'Benchmark';
  static const String _benchmarkPrefix = 'Benchmark:';

  final List<String> _filters = [
    'All',
    _benchmarkFilter,
    '2-Sentence Summary',
    'Key Events',
    'Action Items',
    'Custom',
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final data = await DatabaseService.instance.getAllSummaries();
    if (!mounted) return;
    setState(() {
      _records = data;
      _isLoading = false;
    });
    _applyFilters();
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase().trim();

    setState(() {
      _filteredRecords = _records.where((record) {
        final bool isBenchmark = record.taskType.startsWith(_benchmarkPrefix);

        final bool matchesFilter;
        if (_selectedFilter == 'All') {
          matchesFilter = true;
        } else if (_selectedFilter == _benchmarkFilter) {
          matchesFilter = isBenchmark;
        } else {
          matchesFilter = record.taskType == _selectedFilter;
        }

        final matchesQuery = query.isEmpty ||
            record.generatedSummary.toLowerCase().contains(query) ||
            record.originalText.toLowerCase().contains(query) ||
            record.taskType.toLowerCase().contains(query) ||
            (record.modelName?.toLowerCase().contains(query) ?? false) ||
            (record.engineType?.toLowerCase().contains(query) ?? false);

        return matchesFilter && matchesQuery;
      }).toList();
    });
  }

  Future<void> _deleteRecord(int id) async {
    await DatabaseService.instance.deleteSummary(id);
    _loadHistory();
    _showSnackBar('Record removed.');
  }

  void _showSnackBar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E1E1E),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF121212);
    const surfaceColor = Color(0xFF1E1E1E);
    const accentBlue = Color(0xFF90CAF9);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Saved Summaries',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Search summaries, models, or text...',
                    hintStyle: TextStyle(color: Colors.white38),
                    prefixIcon: Icon(Icons.search_rounded, color: Colors.white38),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final filter = _filters[index];
                  final isSelected = _selectedFilter == filter;
                  return ChoiceChip(
                    label: Text(filter),
                    selected: isSelected,
                    selectedColor: accentBlue.withValues(alpha: 0.25),
                    backgroundColor: surfaceColor,
                    labelStyle: TextStyle(
                      color: isSelected ? accentBlue : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: isSelected ? accentBlue : Colors.white24,
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedFilter = filter);
                        _applyFilters();
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: accentBlue),
                    )
                  : _filteredRecords.isEmpty
                      ? const Center(
                          child: Text(
                            'No saved summaries found.',
                            style: TextStyle(color: Colors.white38, fontSize: 14),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _filteredRecords.length,
                          itemBuilder: (context, index) {
                            final record = _filteredRecords[index];
                            return _buildRecordCard(record, surfaceColor, accentBlue);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordCard(
    SummaryRecord record,
    Color surfaceColor,
    Color accentBlue,
  ) {
    return Container(
      key: PageStorageKey('history_tile_${record.id}'),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accentBlue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        record.taskType,
                        style: TextStyle(
                          color: accentBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (record.modelName != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          record.modelName!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDate(record.createdAt),
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            record.generatedSummary,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          if (record.latencySeconds != null || record.tokensPerSecond != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF121212),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Latency: ${record.latencySeconds?.toStringAsFixed(2) ?? '--'}s',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  Text(
                    'TTFT: ${record.ttftSeconds?.toStringAsFixed(2) ?? '--'}s',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  Text(
                    'Speed: ${record.tokensPerSecond?.toStringAsFixed(1) ?? '--'} tok/s',
                    style: TextStyle(
                      color: accentBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: PageStorageKey('exp_${record.id}'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(top: 6, bottom: 8),
              title: const Text(
                'View Original Passage',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              iconColor: Colors.white60,
              collapsedIconColor: Colors.white38,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121212),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: SelectableText(
                    record.originalText,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: Icon(Icons.copy_rounded, size: 18, color: accentBlue),
                tooltip: 'Copy Summary',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: record.generatedSummary));
                  _showSnackBar('Copied to clipboard.');
                },
              ),
              const SizedBox(width: 16),
              if (record.id != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                  tooltip: 'Delete Record',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _deleteRecord(record.id!),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}