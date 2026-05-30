import 'package:flutter/material.dart';
import 'package:flutter_client/core/constants.dart';

class HelpTooltip extends StatelessWidget {
  final String message;
  final Widget? child;

  const HelpTooltip({
    super.key,
    required this.message,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      decoration: BoxDecoration(
        color: AppColors.brandNavy,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(color: Colors.white, fontSize: 12),
      preferBelow: true,
      child: child ?? Icon(Icons.help_outline, size: 16, color: AppColors.textMuted),
    );
  }
}

class LabelWithHelp extends StatelessWidget {
  final String label;
  final String helpText;
  final bool isRequired;

  const LabelWithHelp({
    super.key,
    required this.label,
    required this.helpText,
    this.isRequired = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: AppTextStyles.label),
        if (isRequired) Text(' *', style: TextStyle(color: AppColors.error)),
        SizedBox(width: 4),
        HelpTooltip(message: helpText),
      ],
    );
  }
}
