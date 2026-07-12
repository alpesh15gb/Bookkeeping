/// The ApexBooks logo/wordmark shown at the top of auth screens.
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({super.key, this.tagline = 'Next Generation ERP'});
  final String tagline;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(ApexRadius.lg),
          ),
          child: const Icon(
            Icons.menu_book_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(height: ApexSpacing.md),
        Text(
          'ApexBooks',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(
          tagline,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colors.textMuted,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

/// A centered, scrollable auth-card wrapper that constrains content width and
/// handles narrow viewports gracefully.
///
/// On wide (desktop) viewports it renders a two-pane layout: a branded value
/// panel on the left and the form card on the right. On narrow viewports it
/// falls back to a single centered card.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final formCard = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: ApexSpacing.xl,
          vertical: ApexSpacing.xxl,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(ApexSpacing.xxl),
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              borderRadius: BorderRadius.circular(ApexRadius.xl),
              border: Border.all(color: colors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 900) return formCard;
            return Row(
              children: [
                Expanded(flex: 5, child: _BrandPanel(colors: colors)),
                Expanded(flex: 4, child: formCard),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.colors});
  final ApexColors colors;

  static const _points = [
    (
      'GST-ready invoicing',
      'CGST/SGST/IGST, e-invoice, and TDS handled automatically.',
    ),
    (
      'Real-time books',
      'Every invoice and bill posts to the ledger instantly.',
    ),
    ('Built for speed', 'Keyboard-first workflows for high-volume data entry.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary,
            HSLColor.fromAHSL(
              1.0,
              HSLColor.fromColor(colors.primary).hue,
              HSLColor.fromColor(colors.primary).saturation * 0.7,
              HSLColor.fromColor(colors.primary).lightness * 0.5,
            ).toColor(),
          ],
        ),
      ),
      padding: const EdgeInsets.all(56),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(ApexRadius.md),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              const Text(
                'ApexBooks',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          const Text(
            'The accounting platform\nbuilt for modern businesses.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              height: 1.25,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 36),
          for (final p in _points)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.$1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p.$2,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
