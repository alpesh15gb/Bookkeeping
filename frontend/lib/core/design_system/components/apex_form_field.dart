/// Consistent form field components with validation, error states, and accessibility.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/responsive.dart';

/// A labeled text field with consistent styling, validation, and error display.
class ApexTextField extends StatelessWidget {
  const ApexTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.suffix,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.readOnly = false,
    this.autofillHints,
    this.validator,
    this.onFieldSubmitted,
    this.onChanged,
    this.onTap,
    this.focusNode,
    this.inputFormatters,
    this.initialValue,
    this.maxLength,
    this.counterText,
    this.expands = false,
    this.contentPadding,
  });

  final TextEditingController? controller;
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final Widget? suffix;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final int? minLines;
  final bool enabled;
  final bool readOnly;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final String? initialValue;
  final int? maxLength;
  final String? counterText;
  final bool expands;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final textTheme = Theme.of(context).textTheme;

    final effectiveController = controller;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: effectiveController,
          initialValue: controller == null ? initialValue : null,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          maxLines: maxLines,
          minLines: minLines,
          enabled: enabled && !readOnly,
          readOnly: readOnly,
          autofillHints: autofillHints,
          validator: validator,
          onFieldSubmitted: onFieldSubmitted,
          onChanged: onChanged,
          onTap: onTap,
          focusNode: focusNode,
          inputFormatters: inputFormatters,
          maxLength: maxLength,
          expands: expands,
          style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, color: colors.textMuted, size: 20)
                : null,
            suffixIcon: suffixIcon,
            suffix: suffix,
            counterText: counterText,
            filled: true,
            fillColor: enabled ? colors.surface : colors.surfaceMuted,
            contentPadding: contentPadding ??
                EdgeInsets.symmetric(
                  horizontal: isMobile ? 14 : 16,
                  vertical: isMobile ? 14 : 16,
                ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.border, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.border, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.danger, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.danger, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.border.withValues(alpha: 0.5), width: 1),
            ),
            errorStyle: textTheme.bodySmall?.copyWith(color: colors.danger),
            floatingLabelBehavior: FloatingLabelBehavior.never,
          ),
        ),
      ],
    );
  }
}

/// A dropdown/select field with consistent styling.
class ApexDropdownField<T> extends StatelessWidget {
  const ApexDropdownField({
    super.key,
    required this.label,
    required this.items,
    this.value,
    this.onChanged,
    this.hint,
    this.validator,
    this.enabled = true,
    this.prefixIcon,
    this.searchable = false,
    this.itemBuilder,
  });

  final String label;
  final List<DropdownMenuItem<T>> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final String? Function(T?)? validator;
  final bool enabled;
  final IconData? prefixIcon;
  final bool searchable;
  final Widget Function(BuildContext, T?)? itemBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<T>(
          initialValue: value,
          items: items,
          onChanged: enabled ? onChanged : null,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, color: colors.textMuted, size: 20)
                : null,
            filled: true,
            fillColor: enabled ? colors.surface : colors.surfaceMuted,
            contentPadding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 16,
              vertical: isMobile ? 14 : 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.border, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.border, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.danger, width: 1),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.border.withValues(alpha: 0.5), width: 1),
            ),
            errorStyle: textTheme.bodySmall?.copyWith(color: colors.danger),
          ),
          style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
          dropdownColor: colors.surface,
          icon: Icon(Icons.keyboard_arrow_down, color: colors.textSecondary),
          isExpanded: true,
          menuMaxHeight: 300,
        ),
      ],
    );
  }
}

/// A date picker field with consistent styling.
class ApexDateField extends StatelessWidget {
  const ApexDateField({
    super.key,
    required this.label,
    required this.value,
    this.onChanged,
    this.hint,
    this.validator,
    this.enabled = true,
    this.firstDate,
    this.lastDate,
    this.helpText,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?>? onChanged;
  final String? hint;
  final String? Function(DateTime?)? validator;
  final bool enabled;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String? helpText;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final textTheme = Theme.of(context).textTheme;

    final formattedValue = value != null
        ? '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}'
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: enabled ? () => _showDatePicker(context) : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 16,
              vertical: isMobile ? 14 : 16,
            ),
            decoration: BoxDecoration(
              color: enabled ? colors.surface : colors.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: enabled ? colors.border : colors.border.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 20, color: colors.textMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    formattedValue.isEmpty ? (hint ?? 'Select date') : formattedValue,
                    style: textTheme.bodyMedium?.copyWith(
                      color: formattedValue.isEmpty ? colors.textMuted : colors.textPrimary,
                    ),
                  ),
                ),
                if (value != null && enabled)
                  IconButton(
                    icon: Icon(Icons.clear, size: 18, color: colors.textMuted),
                    onPressed: () => onChanged?.call(null),
                    tooltip: 'Clear date',
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
        ),
        if (helpText != null) ...[
          const SizedBox(height: 4),
          Text(helpText!, style: textTheme.bodySmall?.copyWith(color: colors.textMuted)),
        ],
      ],
    );
  }

  Future<void> _showDatePicker(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? DateTime.now(),
      firstDate: firstDate ?? DateTime(2000),
      lastDate: lastDate ?? DateTime(2100),
      helpText: helpText ?? 'Select date',
      builder: (context, child) {
        final colors = apexColors(context);
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: colors.primary,
              onPrimary: colors.onPrimary,
              surface: colors.surface,
              onSurface: colors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != value) {
      onChanged?.call(picked);
    }
  }
}

/// A monetary amount field with Indian formatting.
class ApexMonetaryField extends StatelessWidget {
  const ApexMonetaryField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.validator,
    this.enabled = true,
    this.onChanged,
    this.prefix = '₹',
    this.maxValue,
    this.decimalPlaces = 2,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? Function(String?)? validator;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final String prefix;
  final double? maxValue;
  final int decimalPlaces;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          enabled: enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            _DecimalTextInputFormatter(decimalPlaces: decimalPlaces),
            if (maxValue != null) _MaxValueTextInputFormatter(maxValue: maxValue!),
          ],
          validator: validator,
          onChanged: onChanged,
          style: textTheme.bodyMedium?.copyWith(
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
            prefixText: '$prefix ',
            prefixStyle: textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            filled: true,
            fillColor: enabled ? colors.surface : colors.surfaceMuted,
            contentPadding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 16,
              vertical: isMobile ? 14 : 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.border, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.border, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.danger, width: 1),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.border.withValues(alpha: 0.5), width: 1),
            ),
            errorStyle: textTheme.bodySmall?.copyWith(color: colors.danger),
          ),
        ),
      ],
    );
  }
}

class _DecimalTextInputFormatter extends TextInputFormatter {
  const _DecimalTextInputFormatter({required this.decimalPlaces});
  final int decimalPlaces;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    // Allow only one decimal point
    if (text.contains('.') && text.split('.').length > 2) {
      return oldValue;
    }

    // Check decimal places
    if (text.contains('.')) {
      final decimalPart = text.split('.')[1];
      if (decimalPart.length > decimalPlaces) {
        return oldValue;
      }
    }

    // Prevent leading zeros (except for "0.")
    if (text.length > 1 && text.startsWith('0') && !text.startsWith('0.')) {
      return oldValue;
    }

    return newValue;
  }
}

class _MaxValueTextInputFormatter extends TextInputFormatter {
  const _MaxValueTextInputFormatter({required this.maxValue});
  final double maxValue;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final value = double.tryParse(text);
    if (value != null && value > maxValue) {
      return oldValue;
    }
    return newValue;
  }
}

/// A searchable autocomplete field for contacts/products.
class ApexSearchField<T> extends StatefulWidget {
  const ApexSearchField({
    super.key,
    required this.label,
    required this.suggestions,
    this.value,
    this.onChanged,
    this.onSelected,
    this.hint,
    this.validator,
    this.enabled = true,
    required this.getLabel,
    this.getSubtitle,
    this.prefixIcon,
  });

  final String label;
  final List<T> suggestions;
  final T? value;
  final ValueChanged<String>? onChanged;
  final ValueChanged<T?>? onSelected;
  final String? hint;
  final String? Function(String?)? validator;
  final bool enabled;
  final String Function(T) getLabel;
  final String Function(T)? getSubtitle;
  final IconData? prefixIcon;

  @override
  State<ApexSearchField<T>> createState() => _ApexSearchFieldState<T>();
}

class _ApexSearchFieldState<T> extends State<ApexSearchField<T>> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  OverlayEntry? _overlayEntry;
  List<T> _filtered = [];
  bool _showOverlay = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSearchChanged);
    _focusNode.addListener(_onFocusChanged);
    if (widget.value != null) {
      _controller.text = widget.getLabel(widget.value as T);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onSearchChanged);
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _controller.text.toLowerCase();
    setState(() {
      _filtered = widget.suggestions
          .where((item) => widget.getLabel(item).toLowerCase().contains(query))
          .toList();
      _showOverlay = _focusNode.hasFocus && _filtered.isNotEmpty;
    });
    _updateOverlay();
    widget.onChanged?.call(_controller.text);
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          setState(() => _showOverlay = false);
          _removeOverlay();
        }
      });
    } else if (_controller.text.isNotEmpty) {
      setState(() => _showOverlay = true);
      _updateOverlay();
    }
  }

  void _updateOverlay() {
    _removeOverlay();
    if (!_showOverlay || _filtered.isEmpty) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => _SuggestionsOverlay<T>(
        suggestions: _filtered,
        getLabel: widget.getLabel,
        getSubtitle: widget.getSubtitle,
        onSelected: (item) {
          _controller.text = widget.getLabel(item);
          widget.onSelected?.call(item);
          _focusNode.unfocus();
        },
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          style: textTheme.labelMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          validator: widget.validator,
          style: textTheme.bodyMedium?.copyWith(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: textTheme.bodyMedium?.copyWith(color: colors.textMuted),
            prefixIcon: widget.prefixIcon != null
                ? Icon(widget.prefixIcon, color: colors.textMuted, size: 20)
                : null,
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: colors.textMuted, size: 20),
                    onPressed: () {
                      _controller.clear();
                      widget.onSelected?.call(null);
                    },
                  )
                : null,
            filled: true,
            fillColor: widget.enabled ? colors.surface : colors.surfaceMuted,
            contentPadding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 16,
              vertical: isMobile ? 14 : 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.border, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.border, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.danger, width: 1),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colors.border.withValues(alpha: 0.5), width: 1),
            ),
            errorStyle: textTheme.bodySmall?.copyWith(color: colors.danger),
          ),
        ),
      ],
    );
  }
}

class _SuggestionsOverlay<T> extends StatelessWidget {
  const _SuggestionsOverlay({
    required this.suggestions,
    required this.getLabel,
    this.getSubtitle,
    required this.onSelected,
  });

  final List<T> suggestions;
  final String Function(T) getLabel;
  final String Function(T)? getSubtitle;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return Positioned(
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            shrinkWrap: true,
            itemCount: suggestions.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: colors.border),
            itemBuilder: (context, index) {
              final item = suggestions[index];
              return ListTile(
                title: Text(getLabel(item)),
                subtitle: getSubtitle != null ? Text(getSubtitle!(item)) : null,
                onTap: () => onSelected(item),
                dense: true,
              );
            },
          ),
        ),
      ),
    );
  }
}