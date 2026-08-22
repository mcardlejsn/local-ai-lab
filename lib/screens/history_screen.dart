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
  late Future<List<SummaryRecord>> _summariesFuture;

  @override
  void initState() {
    super.initState();
    _loadSummaries();
  }

  void _loadSummaries() {
    setState(() {
      _summariesFuture = DatabaseService.instance.getAllSummaries();
    });
  }

  Future<void> _deleteRecord(int id) async {
    await DatabaseService.instance.deleteSummary(id);
    _loadSummaries();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Record deleted', style: TextStyle(fontSize: 16)),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFFC62828),
        ),
      );
    }
  }

  Future<void> _copyText(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label copied to clipboard', style: const TextStyle(fontSize: 16)),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF2E7D32),
        ),
      );
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    const bgDark = Color(0xFF121212);
    const surfaceDark = Color(0xFF1E1E1E);
    const borderHighContrast = Color(0xFF888888);
    const primaryAccent = Color(0xFF90CAF9);
    const textHighContrast = Color(0xFFFFFFFF);

    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        title: const Text(
          'Saved Summaries',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textHighContrast),
        ),
        backgroundColor: surfaceDark,
        elevation: 2,
        iconTheme: const IconThemeData(color: textHighContrast),
      ),
      body: SafeArea(
        child: FutureBuilder<List<SummaryRecord>>(
          future: _summariesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(primaryAccent),
                ),
              );
            }

            final summaries = snapshot.data ?? [];
            if (summaries.isEmpty) {
              return const Center(
                child: Text(
                  'No saved summaries yet.',
                  style: TextStyle(fontSize: 18, color: Color(0xFFAAAAAA)),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: summaries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final item = summaries[index];
                return Container(
                  decoration: BoxDecoration(
                    color: surfaceDark,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderHighContrast, width: 1.5),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1565C0),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.taskType,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: textHighContrast,
                              ),
                            ),
                          ),
                          Text(
                            _formatDateTime(item.createdAt),
                            style: const TextStyle(fontSize: 14, color: Color(0xFFAAAAAA)),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.copy, size: 20, color: primaryAccent),
                                tooltip: 'Copy Summary',
                                onPressed: () => _copyText(item.generatedSummary, 'Summary'),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 22, color: Color(0xFFFF8A80)),
                                tooltip: 'Delete Record',
                                onPressed: () => _deleteRecord(item.id!),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(color: borderHighContrast, height: 16),

                      // Generated Output
                      const Text(
                        'SUMMARY',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: primaryAccent,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        item.generatedSummary,
                        style: const TextStyle(fontSize: 16, color: textHighContrast, height: 1.4),
                      ),
                      const SizedBox(height: 12),

                      // Original Text Preview (Expandable)
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          title: const Text(
                            'View Original Notes',
                            style: TextStyle(fontSize: 14, color: Color(0xFFAAAAAA)),
                          ),
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF121212),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF444444)),
                              ),
                              child: SelectableText(
                                item.originalText,
                                style: const TextStyle(fontSize: 15, color: Color(0xFFCCCCCC), height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}