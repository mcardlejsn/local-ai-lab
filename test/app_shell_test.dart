import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/screens/app_shell.dart';
import 'package:local_ai_summarizer/screens/settings_screen.dart';

void main() {
  testWidgets('shell exposes four lazy state-preserving destinations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(pageBuilder: (index, _) => _ShellProbe(index: index)),
      ),
    );

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
    expect(find.text('Compare'), findsOneWidget);
    expect(find.text('Models'), findsOneWidget);
    expect(find.text('Results'), findsOneWidget);
    expect(find.byKey(const Key('page-0')), findsOneWidget);
    expect(find.byKey(const Key('page-1')), findsNothing);

    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-1')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('field-1')),
      'retained benchmark state',
    );
    await tester.tap(find.text('Models'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();

    expect(find.text('retained benchmark state'), findsOneWidget);
  });

  testWidgets('Settings reports the active theme foundation as read-only', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Color theme'), findsOneWidget);
    expect(find.text('AI Blue'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}

class _ShellProbe extends StatefulWidget {
  const _ShellProbe({required this.index});

  final int index;

  @override
  State<_ShellProbe> createState() => _ShellProbeState();
}

class _ShellProbeState extends State<_ShellProbe> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: Key('page-${widget.index}'),
      body: TextField(key: Key('field-${widget.index}')),
    );
  }
}
