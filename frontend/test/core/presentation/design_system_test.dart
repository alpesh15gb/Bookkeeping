/// Design system tests.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/core/presentation/design_system/components/apex_button.dart';
import 'package:apexbooks/core/presentation/design_system/components/apex_card.dart';
import 'package:apexbooks/core/presentation/design_system/components/apex_status_badge.dart';
import 'package:apexbooks/core/presentation/design_system/components/apex_states.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/presentation/design_system/theme/app_theme.dart';
import 'package:apexbooks/core/presentation/design_system/tokens/app_spacing.dart';

Widget _wrap(Widget w) =>
    MaterialApp(theme: buildApexTheme(Brightness.light), home: w);

void main() {
  group('AppTheme', () {
    test('light theme creates without error', () {
      final theme = buildApexTheme(Brightness.light);
      expect(theme.colorScheme.primary, isNotNull);
    });

    test('dark theme creates without error', () {
      final theme = buildApexTheme(Brightness.dark);
      expect(theme.colorScheme.primary, isNotNull);
    });

    test('ApexColors extension is present in light theme', () {
      final theme = buildApexTheme(Brightness.light);
      final apex = theme.extension<ApexColors>();
      expect(apex, isNotNull);
      expect(apex!.primary, isNotNull);
    });
  });

  group('ApexButton', () {
    testWidgets('primary button renders label', (t) async {
      await t.pumpWidget(_wrap(const ApexButton.primary(label: 'Save')));
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('primary loading shows spinner', (t) async {
      await t.pumpWidget(
        _wrap(
          ApexButton.primary(label: 'Save', loading: true, onPressed: () {}),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('disabled button does not fire onPressed', (t) async {
      var fired = false;
      await t.pumpWidget(
        _wrap(ApexButton.primary(label: 'Tap', onPressed: () => fired = true)),
      );
      await t.tap(find.text('Tap'));
      expect(fired, true);
    });

    testWidgets('secondary button renders', (t) async {
      await t.pumpWidget(_wrap(const ApexButton.secondary(label: 'Cancel')));
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('danger button renders', (t) async {
      await t.pumpWidget(_wrap(const ApexButton.danger(label: 'Delete')));
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  group('ApexCard', () {
    testWidgets('standard card renders child', (t) async {
      await t.pumpWidget(_wrap(const ApexCard(child: Text('Content'))));
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('highlighted card has border', (t) async {
      await t.pumpWidget(
        _wrap(
          const ApexCard(
            variant: ApexCardVariant.highlighted,
            child: Text('Highlighted'),
          ),
        ),
      );
      expect(find.text('Highlighted'), findsOneWidget);
    });
  });

  group('ApexStatusBadge', () {
    testWidgets('renders label', (t) async {
      await t.pumpWidget(
        _wrap(
          const ApexStatusBadge(label: 'Active', tone: ApexBadgeTone.success),
        ),
      );
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('sync badge renders', (t) async {
      await t.pumpWidget(_wrap(const ApexSyncBadge(status: 'synced')));
      expect(find.text('Synced'), findsOneWidget);
    });

    testWidgets('sync badge with count', (t) async {
      await t.pumpWidget(
        _wrap(const ApexSyncBadge(status: 'pending', count: 5)),
      );
      expect(find.text('5 pending'), findsOneWidget);
    });
  });

  group('ApexEmptyState', () {
    testWidgets('renders title and action', (t) async {
      await t.pumpWidget(
        _wrap(
          ApexEmptyState(title: 'No data', actionLabel: 'Add', onAction: () {}),
        ),
      );
      expect(find.text('No data'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
    });
  });

  group('AppSpacing', () {
    test('values are positive', () {
      expect(AppSpacing.xs, greaterThan(0));
      expect(AppSpacing.lg, greaterThan(AppSpacing.sm));
      expect(AppSpacing.xxl, greaterThan(AppSpacing.lg));
    });
  });
}
