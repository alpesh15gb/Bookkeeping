/// Widget tests that prove the mobile card layouts preserve every desktop
/// table column, the status badge, and the sort affordance for Bills and
/// Purchase Returns.
///
/// These render the public [BillTableBody] / [PurchaseReturnTableBody] at a
/// mobile viewport (< 600 logical px) which activates the `_Mobile*List` card
/// branch, then assert the columns and sort chips are present.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:apexbooks/core/formatting/number_formatting.dart';
import 'package:apexbooks/core/tables/table_column.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/app_theme.dart';
import 'package:apexbooks/features/purchases/purchase_returns/models/purchase_return.dart';
import 'package:apexbooks/features/purchases/purchase_returns/models/purchase_return_status.dart';
import 'package:apexbooks/features/purchases/purchase_returns/presentation/purchase_return_table_body.dart';
import 'package:apexbooks/features/purchases/vendor_bills/models/bill_status.dart';
import 'package:apexbooks/features/purchases/vendor_bills/models/vendor_bill.dart';
import 'package:apexbooks/features/purchases/vendor_bills/presentation/bill_table_body.dart';

final _fmt = NumberFormatter();
const _sort = TableSort(columnId: 'total');

Future<void> _pumpMobile(
  WidgetTester tester,
  Widget child,
) async {
  // Logical viewport 400x800 → forces every `width < 600` mobile branch.
  tester.view.physicalSize = const Size(400 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final colors = apexLightTheme().extension<ApexColors>()!;
  await tester.pumpWidget(
    MaterialApp(
      theme: apexLightTheme(),
      home: Scaffold(body: Center(child: SizedBox(width: 400, height: 800, child: child))),
    ),
  );
  expect(colors, isNotNull);
}

void main() {
  group('BillTableBody mobile card layout', () {
    testWidgets('shows every desktop column plus the sort chips', (tester) async {
      await _pumpMobile(
        tester,
        BillTableBody(
          items: [
            const VendorBillListItem(
              id: 'b-1',
              billNumber: 'BILL-100',
              issueDate: '2024-04-01',
              dueDate: '2024-04-30',
              status: BillStatus.unpaid,
              total: 1250.00,
              amountPaid: 0,
              contactName: 'Vendor One',
            ),
          ],
          sort: _sort,
          onSort: (_) {},
          selectedId: null,
          onSelect: (_) {},
          fmt: _fmt,
          colors: apexLightTheme().extension<ApexColors>()!,
        ),
      );

      // Desktop columns: Bill Number, Vendor, Date/Due, Total, Status.
      expect(find.text('BILL-100'), findsOneWidget); // Bill Number
      expect(find.text('Vendor One'), findsOneWidget); // Vendor
      expect(find.textContaining('2024-04-01'), findsOneWidget); // Date/Due
      expect(find.text('₹1,250.00'), findsOneWidget); // Total
      expect(find.text('UNPAID'), findsOneWidget); // Status badge

      // Sort chips (Number, Date, Amount, Vendor) are present and interactive.
      expect(find.text('Number'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('Vendor'), findsOneWidget);

      // Tapping the Amount chip re-invokes onSort with the total column.
      var tapped = '';
      await _pumpMobile(
        tester,
        BillTableBody(
          items: const [],
          sort: _sort,
          onSort: (col) => tapped = col,
          selectedId: null,
          onSelect: (_) {},
          fmt: _fmt,
          colors: apexLightTheme().extension<ApexColors>()!,
        ),
      );
      await tester.tap(find.text('Amount'));
      expect(tapped, 'total');
    });
  });

  group('PurchaseReturnTableBody mobile card layout', () {
    testWidgets('shows every desktop column plus the sort chips', (tester) async {
      await _pumpMobile(
        tester,
        PurchaseReturnTableBody(
          items: [
            const PurchaseReturnListItem(
              id: 'pr-1',
              returnNumber: 'PR-100',
              returnDate: '2024-04-01',
              status: PurchaseReturnStatus.posted,
              total: 800.00,
              contactName: 'Vendor Two',
            ),
          ],
          sort: _sort,
          onSort: (_) {},
          selectedId: null,
          onSelect: (_) {},
          fmt: _fmt,
          colors: apexLightTheme().extension<ApexColors>()!,
        ),
      );

      // Desktop columns: Return No., Vendor, Return Date, Total, Status.
      expect(find.text('PR-100'), findsOneWidget); // Return No.
      expect(find.text('Vendor Two'), findsOneWidget); // Vendor
      expect(find.textContaining('2024-04-01'), findsOneWidget); // Return Date
      expect(find.textContaining('₹800.00'), findsOneWidget); // Total
      expect(find.text('POSTED'), findsOneWidget); // Status badge

      // Sort chips (Number, Date, Amount, Vendor) are present and interactive.
      expect(find.text('Number'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('Vendor'), findsOneWidget);

      var tapped = '';
      await _pumpMobile(
        tester,
        PurchaseReturnTableBody(
          items: const [],
          sort: _sort,
          onSort: (col) => tapped = col,
          selectedId: null,
          onSelect: (_) {},
          fmt: _fmt,
          colors: apexLightTheme().extension<ApexColors>()!,
        ),
      );
      await tester.tap(find.text('Amount'));
      expect(tapped, 'total');
    });
  });
}
