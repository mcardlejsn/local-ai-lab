import 'package:flutter/material.dart';

import '../models/benchmark_test_case.dart';
import '../services/model_manager_service.dart';
import 'benchmark_screen.dart';
import 'model_download_screen.dart';
import 'results_screen.dart';
import 'summarizer_screen.dart';

typedef AppShellPageBuilder =
    Widget Function(int destinationIndex, ModelManagerService modelManager);

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.pageBuilder});

  /// Allows focused widget tests to exercise shell navigation without starting
  /// platform inference, storage, or database services.
  final AppShellPageBuilder? pageBuilder;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const int _destinationCount = 4;

  late final ModelManagerService _modelManager;
  late final ValueNotifier<BenchmarkTestCase?> _playgroundTestCase;
  late final List<Widget?> _pages;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _modelManager = ModelManagerService();
    _playgroundTestCase = ValueNotifier<BenchmarkTestCase?>(null);
    _pages = List<Widget?>.filled(_destinationCount, null);
    _pages[0] = _buildPage(0);
  }

  Widget _buildPage(int index) {
    final testBuilder = widget.pageBuilder;
    if (testBuilder != null) {
      return testBuilder(index, _modelManager);
    }

    return switch (index) {
      0 => SummarizerScreen(
        modelManager: _modelManager,
        onUseInBenchmark: _useInBenchmark,
      ),
      1 => BenchmarkScreen(
        modelManager: _modelManager,
        playgroundTestCase: _playgroundTestCase,
      ),
      2 => ModelDownloadScreen(modelManager: _modelManager),
      3 => const ResultsScreen(),
      _ => throw RangeError.index(index, _pages, 'index'),
    };
  }

  void _useInBenchmark(BenchmarkTestCase testCase) {
    _playgroundTestCase.value = testCase;
    setState(() {
      _pages[1] ??= _buildPage(1);
      _selectedIndex = 1;
    });
  }

  @override
  void dispose() {
    _playgroundTestCase.dispose();
    super.dispose();
  }

  void _selectDestination(int index) {
    if (index == _selectedIndex) return;

    setState(() {
      _pages[index] ??= _buildPage(index);
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [for (final page in _pages) page ?? const SizedBox.shrink()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectDestination,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Test',
          ),
          NavigationDestination(
            icon: Icon(Icons.speed_outlined),
            selectedIcon: Icon(Icons.speed),
            label: 'Compare',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_in_ar_outlined),
            selectedIcon: Icon(Icons.view_in_ar),
            label: 'Models',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Results',
          ),
        ],
      ),
    );
  }
}
