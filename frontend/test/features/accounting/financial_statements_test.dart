// Tests for Financial Statements — P&L, Balance Sheet.
// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/accounting/financial_statements/models/profit_loss.dart';
import 'package:apexbooks/features/accounting/financial_statements/models/balance_sheet.dart';

void main() {
  group('ProfitLossReport', () {
    test('fromJson', () {
      final pl = ProfitLossReport.fromJson({
        'total_revenue': '50000',
        'total_expenses': '30000',
        'net_profit': '20000',
        'revenue_lines': [
          {'account_name': 'Sales', 'account_code': '40001', 'amount': '50000'},
        ],
        'expense_lines': [
          {'account_name': 'Rent', 'account_code': '50001', 'amount': '30000'},
        ],
      });
      expect(pl.totalRevenue, 50000);
      expect(pl.totalExpenses, 30000);
      expect(pl.netProfit, 20000);
      expect(pl.isProfitable, true);
    });

    test('isProfitable false when loss', () {
      final pl = ProfitLossReport(
        totalRevenue: 10000,
        totalExpenses: 15000,
        netProfit: -5000,
      );
      expect(pl.isProfitable, false);
    });
  });

  group('BalanceSheetReport', () {
    test('fromJson', () {
      final bs = BalanceSheetReport.fromJson({
        'total_assets': '100000',
        'total_liabilities': '40000',
        // Backend total_equity includes the current-period profit line.
        'total_equity': '60000',
        'net_profit': '10000',
        'assets': [
          {'account_name': 'Cash', 'account_code': '10001', 'balance': '50000'},
          {'account_name': 'Bank', 'account_code': '10002', 'balance': '50000'},
        ],
        'liabilities': [
          {'account_name': 'AP', 'account_code': '20001', 'balance': '40000'},
        ],
        'equity': [
          {
            'account_name': 'Capital',
            'account_code': '30001',
            'balance': '50000',
          },
          {
            'account_name': 'Net Profit',
            'account_code': '--',
            'balance': '10000',
          },
        ],
      });
      expect(bs.totalAssets, 100000);
      expect(bs.totalLiabilities, 40000);
      expect(bs.totalEquity, 60000);
      expect(bs.netProfit, 10000);
      expect(bs.totalLiabilitiesEquity, 100000);
      expect(bs.isBalanced, true);
    });

    test('isBalanced false when A != L+E', () {
      final bs = BalanceSheetReport(
        totalAssets: 100000,
        totalLiabilities: 50000,
        totalEquity: 30000,
        netProfit: 10000,
      );
      expect(bs.isBalanced, false);
    });
  });
}
