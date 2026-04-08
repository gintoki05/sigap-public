// Basic smoke test for SIGAP app.
import 'package:flutter_test/flutter_test.dart';

import 'package:sigap/main.dart';

void main() {
  testWidgets('SIGAP app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SigapApp());

    // Verify that the app renders without throwing.
    expect(find.byType(SigapApp), findsOneWidget);
  });
}
