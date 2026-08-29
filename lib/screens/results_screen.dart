import 'package:flutter/material.dart';

import 'history_screen.dart';
import 'saved_benchmark_sessions_screen.dart';
import 'settings_screen.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            color: colorScheme.primary,
            tooltip: 'Settings',
            onPressed: () => openSettings(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Saved runs and benchmark sessions',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Playground runs'),
              subtitle: const Text('Open saved summaries and run telemetry'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HistoryScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.speed_outlined),
              title: const Text('Benchmarks'),
              subtitle: const Text('Open saved benchmark sessions'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SavedBenchmarkSessionsScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
