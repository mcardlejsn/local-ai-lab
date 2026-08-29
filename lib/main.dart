import 'package:flutter/material.dart';

import 'screens/summarizer_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const LocalAiApp());
}

class LocalAiApp extends StatelessWidget {
  const LocalAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local AI Lab',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const SummarizerScreen(),
    );
  }
}
