import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../tokens/typography.dart';
import '../tokens/colors.dart';

class AppAmountText extends StatelessWidget {
  final double amount;
  final TextStyle? style;
  final Color? color;
  final bool showSign;
  final bool showCurrency;
  final String? currencySymbol;

  const AppAmountText({
    super.key,
    required this.amount,
    this.style,
    this.color,
    this.showSign = false,
    this.showCurrency = true,
    this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final formattedAmount = _formatAmount(amount);
    final displayColor = color ?? _getAmountColor();

    return Text(
      formattedAmount,
      style: (style ?? AppTypography.amountSmall).copyWith(
        color: displayColor,
      ),
    );
  }

  String _formatAmount(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: showCurrency ? (currencySymbol ?? '₹') : '',
      decimalDigits: 0,
    );

    String formatted = formatter.format(amount);

    if (showSign && amount > 0) {
      formatted = '+$formatted';
    }

    return formatted;
  }

  Color _getAmountColor() {
    if (amount > 0) return AppColors.revenue;
    if (amount < 0) return AppColors.expense;
    return AppColors.gray600;
  }
}

class AppAmountWithTrend extends StatelessWidget {
  final double amount;
  final double? trendAmount;
  final String? trendLabel;
  final TextStyle? style;

  const AppAmountWithTrend({
    super.key,
    required this.amount,
    this.trendAmount,
    this.trendLabel,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppAmountText(
          amount: amount,
          style: style ?? AppTypography.amountSmall,
        ),
        if (trendAmount != null) ...[
          const SizedBox(height: 2),
          _buildTrend(),
        ],
      ],
    );
  }

  Widget _buildTrend() {
    final isPositive = trendAmount! >= 0;
    final color = isPositive ? AppColors.success : AppColors.error;
    final prefix = isPositive ? '↑' : '↓';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$prefix ${_formatAmount(trendAmount!.abs())}',
          style: AppTypography.labelSmall.copyWith(color: color),
        ),
        if (trendLabel != null) ...[
          const SizedBox(width: 4),
          Text(
            trendLabel!,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.gray400,
            ),
          ),
        ],
      ],
    );
  }

  String _formatAmount(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    );
    return formatter.format(amount);
  }
}
