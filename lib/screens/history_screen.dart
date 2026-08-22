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
  bool _isLoading = true;
  String _selectedFilter = 'All';

  final List<String> _filterCategories = [
    'All',
    '2-Sentence Summary',
    'Key Events',
    'Action Items',
    'Custom',
  ];

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    final query = _searchController.text.trim();
    List<SummaryRecord> list;

    if (query.isEmpty) {
      if (_selectedFilter == 'All') {
        list = await DatabaseService.instance.getAllSummaries();
      } else {
        list = await DatabaseService.instance.searchSummaries('', taskType: _selectedFilter);
      }
    } else {
      list = await DatabaseService.instance.searchSummaries(query, taskType: _selectedFilter);
    }

    setState(() {
      _records = list;
      _isLoading = false;
    });
  }

  Future<void> _deleteRecord(int id) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Summary', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to permanently delete this saved summary?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DatabaseService.instance.deleteSummary(id);
      _loadRecords();
      _showSnackBar('Summary deleted.');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1E1E1E),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
            // Search Input
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => _loadRecords(),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search summaries or source text...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Colors.white54),
                          onPressed: () {
                            _searchController.clear();
                            _loadRecords();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: surfaceColor,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // Task Filter Chips
            SizedBox(
              height: 38,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: _filterCategories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final cat = _filterCategories[i];
                  final isSelected = _selectedFilter == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    selectedColor: accentBlue.withValues(alpha: 0.3),
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
                        setState(() => _selectedFilter = cat);
                        _loadRecords();
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),

            // List of Saved Records
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: accentBlue),
                    )
                  : _records.isEmpty
                      ? const Center(
                          child: Text(
                            'No saved summaries found.',
                            style: TextStyle(color: Colors.white38, fontSize: 14),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _records.length,
                          itemBuilder: (ctx, i) {
                            final record = _records[i];
                            return _buildRecordCard(record, surfaceColor, accentBlue);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordCard(SummaryRecord record, Color surfaceColor, Color accentBlue) {
    final bool hasTelemetry =
        record.latencySeconds != null || record.tokensPerSecond != null;

    final String latencyString = record.latencySeconds != null
        ? '${record.latencySeconds!.toStringAsFixed(2)}s'
        : '--';
    final String ttftString = record.ttftSeconds != null
        ? '${record.ttftSeconds!.toStringAsFixed(2)}s'
        : '--';
    final String speedString = record.tokensPerSecond != null
        ? '${record.tokensPerSecond!.toStringAsFixed(1)} tok/s'
        : '--';

    return Card(
      color: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.white10),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Task Type & Date Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accentBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    record.taskType,
                    style: TextStyle(
                      color: accentBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(
                  _formatTimestamp(record.createdAt),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Summary Content
            SelectableText(
              record.generatedSummary,
              style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 10),

            // Telemetry Badge Row
            if (hasTelemetry) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF121212),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Latency: $latencyString',
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                    Text(
                      'TTFT: $ttftString',
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                    Text(
                      'Speed: $speedString',
                      style: TextStyle(
                        color: accentBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Expandable Original Text Viewer
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'View Original Passage',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121212),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      record.originalText,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10),

            // Card Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(Icons.copy_rounded, size: 18, color: accentBlue),
                  tooltip: 'Copy Summary',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: record.generatedSummary));
                    _showSnackBar('Summary copied to clipboard.');
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                  tooltip: 'Delete',
                  onPressed: () {
                    if (record.id != null) {
                      _deleteRecord(record.id!);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}