/// Reusable form field widgets built on the ApexBooks input theme.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/responsive.dart';

/// A labeled text field with consistent styling, optional prefix icon and
/// built-in error display. Wraps [TextFormField] for use inside [Form].
class ApexTextField extends StatelessWidget {
  const ApexTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.enabled = true,
    this.autofillHints,
    this.validator,
    this.onFieldSubmitted,
    this.onTap,
    this.readOnly = false,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final VoidCallback? onTap;
  final bool readOnly;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveLayout.isMobile(context);
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        suffixIcon: suffixIcon,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: isMobile ? 16 : 14,
        ),
      ),
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      maxLines: obscureText ? 1 : maxLines,
      enabled: enabled,
      readOnly: readOnly,
      autofocus: false,
      focusNode: focusNode,
      autofillHints: autofillHints,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      onTap: onTap,
      style: Theme.of(context).textTheme.bodyLarge,
    );
  }
}

/// A password field with a show/hide toggle.
class ApexPasswordField extends StatefulWidget {
  const ApexPasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.hint = '••••••••',
    this.validator,
    this.onFieldSubmitted,
    this.autofillHints,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;

  @override
  State<ApexPasswordField> createState() => _ApexPasswordFieldState();
}

class _ApexPasswordFieldState extends State<ApexPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return ApexTextField(
      controller: widget.controller,
      label: widget.label,
      hint: widget.hint,
      obscureText: _obscured,
      validator: widget.validator,
      onFieldSubmitted: widget.onFieldSubmitted,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      keyboardType: TextInputType.visiblePassword,
      prefixIcon: Icons.lock_outline_rounded,
      suffixIcon: IconButton(
        icon: Icon(
          _obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: colors.textMuted,
          size: 20,
        ),
        onPressed: () => setState(() => _obscured = !_obscured),
        tooltip: _obscured ? 'Show password' : 'Hide password',
      ),
    );
  }
}

/// A submit button that shows a spinner while [loading] is true and disables
/// itself to prevent duplicate submissions.
class ApexSubmitButton extends StatelessWidget {
  const ApexSubmitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final child = loading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: colors.onPrimary,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 8),
              ],
              Text(label),
            ],
          );

    final btn = FilledButton(
      onPressed: loading ? null : onPressed,
      child: child,
    );
    return expanded ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}
