// Tests for Financial Year — lifecycle, status, year-end close.
// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/accounting/financial_year/models/financial_year.dart';
import 'package:apexbooks/features/accounting/financial_year/models/year_end_dashboard.dart';

void main() {
  group('FinancialYear', () {
    test('isOpen / canClose / canReopen', () {
      const current = FinancialYear(
        id: 'fy1',
        status: 'CURRENT',
        isCurrent: true,
      );
      expect(current.isOpen, true);
      expect(current.canClose, true);
      expect(current.canReopen, false);

      const locked = FinancialYear(id: 'fy2', status: 'LOCKED');
      expect(locked.isLocked, true);
      expect(locked.canReopen, true);
      expect(locked.canClose, false);

      const ready = FinancialYear(id: 'fy3', status: 'READY_TO_CLOSE');
      expect(ready.isReadyToClose, true);
      expect(ready.canClose, true);

      const archived = FinancialYear(id: 'fy4', status: 'ARCHIVED');
      expect(archived.isArchived, true);
      expect(archived.canReopen, true);
    });

    test('fromJson', () {
      final fy = FinancialYear.fromJson({
        'id': 'fy1',
        'tenant_id': 't1',
        'name': 'FY 2025-26',
        'start_date': '2025-04-01',
        'end_date': '2026-03-31',
        'status': 'CURRENT',
        'is_current': true,
        'transaction_count': 150,
      });
      expect(fy.name, 'FY 2025-26');
      expect(fy.isCurrent, true);
      expect(fy.transactionCount, 150);
    });
  });

  group('YearEndDashboard', () {
    test('fromJson', () {
      final d = YearEndDashboard.fromJson({
        'readiness_score': 85,
        'trial_balance_balanced': true,
        'unposted_documents_count': 2,
        'net_profit': '50000',
        'closing_allowed': true,
        'blocking_items': [],
        'financial_year': {
          'id': 'fy1',
          'name': 'FY 2025-26',
          'start_date': '2025-04-01',
          'end_date': '2026-03-31',
          'status': 'CURRENT',
          'is_current': true,
        },
        'unposted_documents': [
          {
            'id': 'inv1',
            'document_type': 'INVOICE',
            'document_number': 'INV-001',
            'date': '2025-07-01',
            'amount': '10000',
          },
          {
            'id': 'bill1',
            'document_type': 'BILL',
            'document_number': 'BILL-001',
            'date': '2025-07-02',
            'amount': '5000',
          },
        ],
      });
      expect(d.readinessScore, 85);
      expect(d.trialBalanceBalanced, true);
      expect(d.closingAllowed, true);
      expect(d.financialYear?.name, 'FY 2025-26');
      expect(d.unpostedDocuments.length, 2);
      expect(d.blockingItems, isEmpty);
    });
  });

  group('OpeningBalanceSnapshot', () {
    test('fromJson', () {
      final snap = OpeningBalanceSnapshot.fromJson({
        'id': 'obs1',
        'account_id': 'acct1',
        'account_type': 'Asset',
        'account_name': 'Cash',
        'account_code': '10001',
        'closing_balance': '50000',
        'direction': 'DEBIT',
      });
      expect(snap.accountName, 'Cash');
      expect(snap.closingBalance, 50000);
      expect(snap.direction, 'DEBIT');
    });
  });

  group('InventoryCarryForward', () {
    test('fromJson', () {
      final cf = InventoryCarryForward.fromJson({
        'id': 'icf1',
        'product_id': 'p1',
        'product_name': 'Widget',
        'product_sku': 'WDG-001',
        'closing_quantity': '100',
        'closing_value': '5000',
        'unit_rate': '50',
      });
      expect(cf.productName, 'Widget');
      expect(cf.closingQuantity, 100);
      expect(cf.closingValue, 5000);
      expect(cf.unitRate, 50);
    });
  });
}
