import 'package:flutter/material.dart';
import 'screens/summarizer_screen.dart';

void main() {
  runApp(const LocalAiApp());
}

class LocalAiApp extends StatelessWidget {
  const LocalAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local AI Summarizer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF90CAF9),
          surface: Color(0xFF1E1E1E),
        ),
      ),
      home: const SummarizerScreen(),
    );
  }
}
