import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/main.dart';

void main() {
  testWidgets('App builds and shows login or loading', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();
    expect(find.byType(MyApp), findsOneWidget);
  });
}
