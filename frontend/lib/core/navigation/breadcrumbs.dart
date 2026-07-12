/// Breadcrumb navigation widget for desktop. Placed above the content area
/// and below the AppBar to show the current location hierarchy.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A breadcrumb (text + optional link).
@immutable
class Breadcrumb {
  const Breadcrumb({required this.label, this.route, this.onTap});
  final String label;
  final String? route;
  final VoidCallback? onTap;
}

/// A horizontal breadcrumb trail.
class Breadcrumbs extends StatelessWidget {
  const Breadcrumbs({super.key, required this.items, this.homeLabel = 'Home'});

  final List<Breadcrumb> items;
  final String homeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // Home link
          InkWell(
            onTap: () => Navigator.of(context).pushNamed('/'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Icon(
                Icons.home_rounded,
                size: 16,
                color: colors.textMuted,
              ),
            ),
          ),
          // Items
          for (var i = 0; i < items.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: colors.textMuted,
              ),
            ),
            InkWell(
              onTap: items[i].onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  items[i].label,
                  style: TextStyle(
                    fontSize: 13,
                    color: i == items.length - 1
                        ? colors.textPrimary
                        : colors.textMuted,
                    fontWeight: i == items.length - 1
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
