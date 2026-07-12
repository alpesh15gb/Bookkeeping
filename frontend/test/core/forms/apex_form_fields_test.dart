// Widget tests for ApexForm field components.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/core/theme/app_theme.dart';
import 'package:apexbooks/core/forms/apex_form.dart';
import 'package:apexbooks/core/forms/dropdown_date_fields.dart';
import 'package:apexbooks/core/forms/gst_percentage_fields.dart';
import 'package:apexbooks/core/forms/money_field.dart';

void main() {
  Widget buildWidget(Widget child) => MaterialApp(
    theme: apexLightTheme(),
    home: Scaffold(body: child),
  );

  testWidgets('ApexGSTField renders with label', (tester) async {
    final controller = ApexFormController<Map<String, dynamic>>((fields) => {});
    await tester.pumpWidget(
      buildWidget(
        ApexForm(
          controller: controller,
          child: Form(
            child: ListView(
              children: [ApexGSTField(name: 'gstin', label: 'GSTIN')],
            ),
          ),
        ),
      ),
    );
    expect(find.text('GSTIN'), findsOneWidget);
  });

  testWidgets('ApexDropdownField renders with options', (tester) async {
    final controller = ApexFormController<Map<String, dynamic>>((fields) => {});
    await tester.pumpWidget(
      buildWidget(
        ApexForm(
          controller: controller,
          child: Form(
            child: ListView(
              children: [
                ApexDropdownField<String>(
                  name: 'type',
                  label: 'Type',
                  options: const ['A', 'B', 'C'],
                  toLabel: (s) => 'Option $s',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Type'), findsOneWidget);
  });

  testWidgets('ApexMoneyField renders with label', (tester) async {
    final controller = ApexFormController<Map<String, dynamic>>((fields) => {});
    await tester.pumpWidget(
      buildWidget(
        ApexForm(
          controller: controller,
          child: Form(
            child: ListView(
              children: [
                ApexMoneyField(
                  name: 'amount',
                  label: 'Amount',
                  initialValue: 100.50,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Amount'), findsOneWidget);
  });
}
