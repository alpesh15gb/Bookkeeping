// Golden / widget test for EntityDetailPage.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_theme.dart';
import 'package:apexbooks/core/widgets/entity_detail_page.dart';

void main() {
  testWidgets('EntityDetailPage renders sections, chips, and timeline', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: apexLightTheme(),
          home: const EntityDetailPage(
            title: 'Test Entity',
            header: Text('Header Widget'),
            chips: [
              DetailChip(label: 'Active', color: Colors.green),
              DetailChip(label: 'Supplier', color: Colors.blue),
            ],
            sections: [
              DetailSection(
                title: 'Contact Info',
                rows: [
                  DetailRow('Phone', '9876543210'),
                  DetailRow('Email', 'test@example.com'),
                ],
              ),
              DetailSection(
                title: 'Address',
                rows: [
                  DetailRow('City', 'Mumbai'),
                  DetailRow('State', 'Maharashtra'),
                ],
              ),
            ],
            timeline: [
              TimelineEntry(
                title: 'Created',
                subtitle: 'Entity was created',
                timestamp: '2025-04-01T10:00:00Z',
                icon: Icons.add_circle_outline,
                color: Colors.green,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Test Entity'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Supplier'), findsOneWidget);
    expect(find.text('Contact Info'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('9876543210'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('test@example.com'), findsOneWidget);
    expect(find.text('Address'), findsOneWidget);
    expect(find.text('City'), findsOneWidget);
    expect(find.text('Mumbai'), findsOneWidget);
    expect(find.text('Created'), findsOneWidget);
  });
}
