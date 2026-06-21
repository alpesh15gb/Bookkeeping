import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/design_system/components/app_button.dart';
import 'package:flutter_client/design_system/components/app_section_header.dart';
import 'package:flutter_client/features/dashboard/widgets/action_required_card.dart';
import 'test_helpers/widget_harness.dart';

void main() {
  final testedSizes = <Size>[
    const Size(1920, 1080),
    const Size(1600, 900),
    const Size(1440, 900),
    const Size(1366, 768),
    const Size(1024, 768),
    const Size(768, 1024),
    const Size(430, 932),
    const Size(390, 844),
    const Size(360, 800),
  ];

  testWidgets('ShellScreen lays out at supported breakpoints', (tester) async {
    for (final size in testedSizes) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(buildShellHarness(size: size));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard content'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'failed at $size');
    }
  });

  testWidgets('AppSectionHeader wraps constrained actions without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpWidget(
      buildWidgetHarness(
        const SizedBox(
          width: 220,
          child: AppSectionHeader(
            title: 'VERY LONG DASHBOARD SECTION TITLE',
            count: 128,
            action: AppButton(label: 'View Details', onPressed: null),
          ),
        ),
      ),
    );

    expect(find.text('VERY LONG DASHBOARD SECTION TITLE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ActionRequiredCard fits narrow dashboard cards', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpWidget(
      buildWidgetHarness(
        const SizedBox(width: 220, child: ActionRequiredCard()),
      ),
    );

    expect(find.text('ACTION REQUIRED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
