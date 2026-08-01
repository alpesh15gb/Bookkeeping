/// ApexBooks state components (empty, error, loading).
library;

import 'package:flutter/material.dart';
import '../tokens/app_spacing.dart';
import 'apex_button.dart';

class ApexEmptyState extends StatelessWidget {
  const ApexEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: AppSpacing.lg),
            ],
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.xl),
              ApexButton.primary(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

class ApexErrorState extends StatelessWidget {
  const ApexErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.details,
  });

  final String message;
  final VoidCallback? onRetry;
  final String? details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (details != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                details!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              ApexButton.secondary(
                label: 'Retry',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ApexLoadingSkeleton extends StatelessWidget {
  const ApexLoadingSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 4,
  });

  final double? width;
  final double? height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: height ?? 14,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Use [ApexPageState.loading], [ApexPageState.error], or
/// [ApexPageState.empty] to render standard page states.
class ApexPageState extends StatelessWidget {
  const ApexPageState.loading({super.key})
    : _variant = 'loading',
      child = null,
      message = null,
      onRetry = null,
      title = null,
      subtitle = null,
      icon = null,
      actionLabel = null,
      onAction = null;

  const ApexPageState.loaded({super.key, required this.child})
    : _variant = 'loaded',
      message = null,
      onRetry = null,
      title = null,
      subtitle = null,
      icon = null,
      actionLabel = null,
      onAction = null;

  const ApexPageState.error({super.key, required this.message, this.onRetry})
    : _variant = 'error',
      child = null,
      title = null,
      subtitle = null,
      icon = null,
      actionLabel = null,
      onAction = null;

  const ApexPageState.empty({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actionLabel,
    this.onAction,
  }) : _variant = 'empty',
       child = null,
       message = null,
       onRetry = null;

  final String _variant;
  final Widget? child;
  final String? message;
  final VoidCallback? onRetry;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    switch (_variant) {
      case 'loading':
        return const Center(child: CircularProgressIndicator());
      case 'loaded':
        return child!;
      case 'error':
        return ApexErrorState(message: message!, onRetry: onRetry);
      case 'empty':
        return ApexEmptyState(
          title: title!,
          subtitle: subtitle,
          icon: icon,
          actionLabel: actionLabel,
          onAction: onAction,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
