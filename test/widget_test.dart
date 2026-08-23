import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/main.dart';
import 'package:local_ai_summarizer/screens/summarizer_screen.dart';

void main() {
  testWidgets('Summarizer screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const LocalAiApp());

    expect(find.byType(SummarizerScreen), findsOneWidget);
  });
}