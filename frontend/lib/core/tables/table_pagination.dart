/// Pagination footer for [ApexDataTable]: page size selector, page navigator,
/// and a "X–Y of Z" summary. Driven by a [Paged] result + [ApexTableController].
library;

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../network/dio_extensions.dart';
import '../theme/app_colors.dart';
import '../theme/responsive.dart';
import 'table_controller.dart';

class ApexPaginationControls extends StatelessWidget {
  const ApexPaginationControls({
    super.key,
    required this.controller,
    required this.paged,
  });

  final ApexTableController controller;
  final Paged<dynamic> paged;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final totalPages = paged.totalPages;
    final page = paged.page;
    final from = paged.total == 0 ? 0 : ((page - 1) * paged.limit) + 1;
    final to = (page * paged.limit).clamp(0, paged.total);
    final isMobile = ResponsiveLayout.isMobile(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(isMobile ? 8 : 16, 8, isMobile ? 8 : 16, 12),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _pageBtn(Icons.first_page_rounded, page > 1 ? () => controller.setPage(1) : null),
                    _pageBtn(Icons.chevron_left_rounded, page > 1 ? () => controller.setPage(page - 1) : null),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('  $page / $totalPages  ', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    _pageBtn(Icons.chevron_right_rounded, page < totalPages ? () => controller.setPage(page + 1) : null),
                    _pageBtn(Icons.last_page_rounded, page < totalPages ? () => controller.setPage(totalPages) : null),
                  ],
                ),
                const SizedBox(height: 8),
                Text('$from–$to of ${paged.total}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textSecondary)),
              ],
            )
          : Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Page size selector
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rows per page',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                // The backend may return a limit not in pageSizeOptions
                // (e.g. 25).  Clamp to the nearest valid option so the
                // DropdownButton assertion doesn't fire.
                value: _closestPageSize(paged.limit),
                underline: const SizedBox.shrink(),
                items: AppConstants.pageSizeOptions
                    .map(
                      (s) => DropdownMenuItem<int>(value: s, child: Text('$s')),
                    )
                    .toList(),
                onChanged: (v) => v == null ? null : controller.setLimit(v),
              ),
            ],
          ),
          Text(
            '$from–$to of ${paged.total}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          // Page navigation
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'First page',
                icon: const Icon(Icons.first_page_rounded),
                onPressed: page > 1 ? () => controller.setPage(1) : null,
              ),
              IconButton(
                tooltip: 'Previous page',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: page > 1 ? () => controller.setPage(page - 1) : null,
              ),
              Text('  $page / $totalPages  '),
              IconButton(
                tooltip: 'Next page',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: page < totalPages
                    ? () => controller.setPage(page + 1)
                    : null,
              ),
              IconButton(
                tooltip: 'Last page',
                icon: const Icon(Icons.last_page_rounded),
                onPressed: page < totalPages
                    ? () => controller.setPage(totalPages)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Returns the closest value from [AppConstants.pageSizeOptions] to [limit],
  /// so the [DropdownButton] never asserts on a server-returned value it can't
  /// display.
  static int _closestPageSize(int limit) {
    var best = AppConstants.pageSizeOptions.first;
    var minDelta = (limit - best).abs();
    for (final opt in AppConstants.pageSizeOptions) {
      final delta = (limit - opt).abs();
      if (delta < minDelta) {
        minDelta = delta;
        best = opt;
      }
    }
    return best;
  }

  Widget _pageBtn(IconData icon, VoidCallback? onPressed) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        icon: Icon(icon, size: 22),
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
