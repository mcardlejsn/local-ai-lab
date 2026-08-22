import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_summarizer/main.dart';

void main() {
  testWidgets('Diagnostic screen renders headline', (WidgetTester tester) async {
    await tester.pumpWidget(const LocalAiApp());

    expect(find.text('On-Device AI Setup'), findsOneWidget);
  });
}