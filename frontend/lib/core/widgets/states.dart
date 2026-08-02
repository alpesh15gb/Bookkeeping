/// Shared empty / error / loading states so every list screen renders the
/// four async states consistently.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A friendly empty-state with an icon, title, optional subtitle and action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ApexSpacing_xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: colors.textMuted),
            ),
            const SizedBox(height: ApexSpacing_lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: ApexSpacing_sm),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: ApexSpacing_xl),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// An error state with a retry affordance.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ApexSpacing_xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.danger.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 32,
                color: colors.danger,
              ),
            ),
            const SizedBox(height: ApexSpacing_lg),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: ApexSpacing_sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: ApexSpacing_xl),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A simple centered spinner used inline (e.g. inside buttons / panels).
class LoadingSpinner extends StatelessWidget {
  const LoadingSpinner({super.key, this.size = 24});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2.4,
        color: apexColors(context).primary,
      ),
    );
  }
}

/// A full-area loading placeholder.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LoadingSpinner(size: 32),
          if (label != null) ...[
            const SizedBox(height: ApexSpacing_md),
            Text(
              label!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: apexColors(context).textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
