/// ApexBooks button component — single source of truth for all button variants.
library;

import 'package:flutter/material.dart';
import '../tokens/app_spacing.dart';

enum ApexButtonVariant { primary, secondary, outline, ghost, danger, icon }

enum ApexButtonSize { sm, md, lg }

class ApexButton extends StatelessWidget {
  const ApexButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.size = ApexButtonSize.md,
    this.loading = false,
    this.fullWidth = false,
    this.semanticLabel,
  }) : variant = ApexButtonVariant.primary;

  const ApexButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.size = ApexButtonSize.md,
    this.loading = false,
    this.fullWidth = false,
    this.semanticLabel,
  }) : variant = ApexButtonVariant.secondary;

  const ApexButton.danger({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.size = ApexButtonSize.md,
    this.loading = false,
    this.fullWidth = false,
    this.semanticLabel,
  }) : variant = ApexButtonVariant.danger;

  const ApexButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.size = ApexButtonSize.md,
    this.fullWidth = false,
    this.semanticLabel,
  }) : variant = ApexButtonVariant.ghost,
       loading = false;

  const ApexButton.icon({
    super.key,
    required this.icon,
    this.onPressed,
    this.semanticLabel,
    this.size = ApexButtonSize.md,
  }) : variant = ApexButtonVariant.icon,
       label = null,
       loading = false,
       fullWidth = false;

  final ApexButtonVariant variant;
  final ApexButtonSize size;
  final String? label;
  final Widget? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool fullWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    switch (variant) {
      case ApexButtonVariant.primary:
        return _styled(
          context,
          FilledButton.icon(
            onPressed: loading ? null : onPressed,
            style: _style(theme),
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : (icon ?? const SizedBox.shrink()),
            label: Text(label ?? '', style: _textStyle(theme)),
          ),
        );
      case ApexButtonVariant.secondary:
      case ApexButtonVariant.outline:
        return _styled(
          context,
          OutlinedButton.icon(
            onPressed: loading ? null : onPressed,
            style: _style(theme),
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : (icon ?? const SizedBox.shrink()),
            label: Text(label ?? ''),
          ),
        );
      case ApexButtonVariant.danger:
        return _styled(
          context,
          FilledButton.icon(
            onPressed: loading ? null : onPressed,
            style: FilledButton.styleFrom(backgroundColor: colors.error),
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : (icon ?? const SizedBox.shrink()),
            label: Text(label ?? ''),
          ),
        );
      case ApexButtonVariant.ghost:
        return _styled(
          context,
          TextButton.icon(
            onPressed: onPressed,
            style: _style(theme),
            icon: icon ?? const SizedBox.shrink(),
            label: Text(label ?? ''),
          ),
        );
      case ApexButtonVariant.icon:
        return IconButton(
          onPressed: onPressed,
          icon: icon ?? const SizedBox.shrink(),
          tooltip: semanticLabel,
          style: _style(theme),
        );
    }
  }

  Widget _styled(BuildContext context, Widget button) {
    if (fullWidth) return SizedBox(width: double.infinity, child: button);
    return button;
  }

  ButtonStyle? _style(ThemeData theme) {
    final h = _height;
    return ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, h)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: _horizontalPadding, vertical: 0),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  double get _height => switch (size) {
    ApexButtonSize.sm => 32,
    ApexButtonSize.md => 40,
    ApexButtonSize.lg => 48,
  };

  double get _horizontalPadding => switch (size) {
    ApexButtonSize.sm => AppSpacing.md,
    ApexButtonSize.md => AppSpacing.lg,
    ApexButtonSize.lg => AppSpacing.xxl,
  };

  TextStyle? _textStyle(ThemeData theme) => theme.textTheme.labelLarge;
}
