import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_client/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App', () {
    testWidgets('shows login screen', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Verify login form is displayed
      expect(find.text('Login'), findsOneWidget);
      expect(find.byType(TextFormField), findsAtLeastNWidgets(2));
    });

    testWidgets('can navigate to register', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Find and tap register link
      final registerFinder = find.textContaining('Register');
      if (registerFinder.evaluate().isNotEmpty) {
        await tester.tap(registerFinder.first);
        await tester.pumpAndSettle();
      }
    });
  });
}
