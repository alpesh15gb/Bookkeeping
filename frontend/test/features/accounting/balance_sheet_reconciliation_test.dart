import 'package:flutter_test/flutter_test.dart';
import 'package:apexbooks/features/accounting/financial_statements/models/balance_sheet.dart';

void main() {
  test('does not double count net profit already included in total equity', () {
    const report = BalanceSheetReport(
      totalAssets: 100000,
      totalLiabilities: 40000,
      totalEquity: 60000,
      netProfit: 10000,
    );

    expect(report.totalLiabilitiesEquity, 100000);
    expect(report.isBalanced, isTrue);
  });
}
