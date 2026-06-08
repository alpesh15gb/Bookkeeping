import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_client/core/constants.dart';
import 'package:flutter_client/views/shared/app_components.dart' show StatusBadge, LoadingState, ErrorState;

// ═══════════════════════════════════════════════════════════════════
// APEXBOOKS DESIGN SYSTEM v4.0
// Modern Business OS Primitives
// ═══════════════════════════════════════════════════════════════════
//
// Every screen in ApexBooks must use these primitives.
// Do not create custom one-off components.
// If you need something new, extend these primitives.
//
// Rules:
// - No shadows on cards (use borders)
// - No gradients (except gold accent on active states)
// - Tabular figures for all amounts
// - Inter font everywhere
// - Data density is a feature
//
// ═══════════════════════════════════════════════════════════════════

// ─── CARD ─────────────────────────────────────────────────────────
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? color;
  final Border? border;
  final double? borderRadius;
  final Color? accentColor;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.border,
    this.borderRadius,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? AppColors.bgSurface,
        borderRadius: borderRadius != null ? BorderRadius.circular(borderRadius!) : AppRadius.card,
        border: border ?? (accentColor != null
            ? Border(
                top: BorderSide(color: accentColor!, width: 3),
                left: const BorderSide(color: AppColors.border),
                right: const BorderSide(color: AppColors.border),
                bottom: const BorderSide(color: AppColors.border),
              )
            : Border.all(color: AppColors.border)),
      ),
      child: child,
    );
  }
}

// ─── SECTION ──────────────────────────────────────────────────────
class AppSection extends StatelessWidget {
  final String title;
  final Widget child;
  final EdgeInsets? padding;
  final Widget? action;

  const AppSection({
    super.key,
    required this.title,
    required this.child,
    this.padding,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            if (action != null) action!,
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

// ─── METRIC (single value) ────────────────────────────────────────
class AppMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final IconData? icon;
  final double? fontSize;
  final String? tooltip;

  const AppMetric({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.icon,
    this.fontSize,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    final text = Text(
      value,
      style: TextStyle(
        fontSize: fontSize ?? 18,
        fontWeight: FontWeight.w700,
        color: c,
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: 0.1,
        height: 1.2,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: c),
              const SizedBox(width: 6),
            ],
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (tooltip != null)
          Tooltip(message: tooltip, child: text)
        else
          text,
      ],
    );
  }
}

// ─── DATA TABLE (dense) ─────────────────────────────────────────
class AppDataTable extends StatelessWidget {
  final List<String> columns;
  final List<List<Widget>> rows;
  final bool showHeader;

  const AppDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bgLight,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
            child: Row(
              children: columns.map((col) {
                return Expanded(
                  child: Text(
                    col.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
        ...rows.map((row) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.borderLight)),
            ),
            child: Row(
              children: row.map((cell) => Expanded(child: cell)).toList(),
            ),
          );
        }).toList(),
      ],
    );
  }
}

// ─── TIMELINE ─────────────────────────────────────────────────────
class AppTimeline extends StatelessWidget {
  final List<AppTimelineItem> items;

  const AppTimeline({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(items.length, (i) {
        final item = items[i];
        final isLast = i == items.length - 1;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: item.color ?? AppColors.brandNavy,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Container(width: 1, height: 32, color: AppColors.borderLight),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                  ),
                  if (item.subtitle != null)
                    Text(
                      item.subtitle!,
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  if (item.date != null)
                    Text(
                      item.date!,
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            if (item.trailing != null) item.trailing!,
          ],
        );
      }),
    );
  }
}

class AppTimelineItem {
  final String title;
  final String? subtitle;
  final String? date;
  final Color? color;
  final Widget? trailing;

  AppTimelineItem({
    required this.title,
    this.subtitle,
    this.date,
    this.color,
    this.trailing,
  });
}

enum AppButtonSize { sm, md, lg }
enum AppButtonVariant { primary, secondary, ghost, danger }

// ─── BUTTON ───────────────────────────────────────────────────────
class AppButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? color;
  final Color? textColor;
  final bool isPrimary;
  final bool isSmall;
  final bool isLoading;
  final AppButtonSize? size;
  final AppButtonVariant? variant;

  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.color,
    this.textColor,
    this.isPrimary = false,
    this.isSmall = false,
    this.isLoading = false,
    this.size,
    this.variant,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveVariant = variant ?? (isPrimary ? AppButtonVariant.primary : AppButtonVariant.secondary);
    final effectiveSize = size ?? (isSmall ? AppButtonSize.sm : AppButtonSize.md);

    Color bg;
    Color fg;
    Border? border;

    switch (effectiveVariant) {
      case AppButtonVariant.primary:
        bg = color ?? AppColors.brandNavy;
        fg = textColor ?? AppColors.textWhite;
        border = null;
        break;
      case AppButtonVariant.secondary:
        bg = color ?? AppColors.bgSurface;
        fg = textColor ?? AppColors.textPrimary;
        border = Border.all(color: AppColors.border);
        break;
      case AppButtonVariant.ghost:
        bg = Colors.transparent;
        fg = textColor ?? AppColors.brandNavy;
        border = null;
        break;
      case AppButtonVariant.danger:
        bg = color ?? AppColors.error;
        fg = textColor ?? AppColors.textWhite;
        border = null;
        break;
    }

    EdgeInsets padding;
    double fontSize;
    double iconSize;

    switch (effectiveSize) {
      case AppButtonSize.sm:
        padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6);
        fontSize = 12;
        iconSize = 14;
        break;
      case AppButtonSize.md:
        padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
        fontSize = 13;
        iconSize = 16;
        break;
      case AppButtonSize.lg:
        padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 14);
        fontSize = 15;
        iconSize = 18;
        break;
    }

    return Material(
      color: bg,
      borderRadius: AppRadius.button,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: AppRadius.button,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppRadius.button,
            border: border,
          ),
          child: isLoading
              ? SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: iconSize, color: fg),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: effectiveVariant == AppButtonVariant.primary || effectiveVariant == AppButtonVariant.danger
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: fg,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─── INPUT ────────────────────────────────────────────────────────
class AppInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? hint;
  final String? label;
  final Widget? prefix;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final bool isDense;

  const AppInput({
    super.key,
    this.controller,
    this.hint,
    this.label,
    this.prefix,
    this.suffix,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.isDense = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        labelText: label,
        prefixIcon: prefix != null ? SizedBox(width: 32, child: Center(child: prefix)) : null,
        suffixIcon: suffix,
        isDense: isDense,
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        border: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: const BorderSide(color: AppColors.borderInput),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: const BorderSide(color: AppColors.borderInput),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.input,
          borderSide: const BorderSide(color: AppColors.brandNavy, width: 1.5),
        ),
        filled: true,
        fillColor: AppColors.bgSurface,
      ),
    );
  }
}

// ─── BAR CHART (simple) ─────────────────────────────────────────
class AppBarChart extends StatelessWidget {
  final List<AppBarData> data;
  final double height;
  final bool showLegend;

  const AppBarChart({
    super.key,
    required this.data,
    this.height = 120,
    this.showLegend = true,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();

    final maxVal = data.map((d) => d.value).reduce((a, b) => a > b ? a : b);
    final max = maxVal > 0 ? maxVal : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLegend && data.isNotEmpty)
          Row(
            children: [
              _legendDot(data.first.color),
              const SizedBox(width: 4),
              Text(data.first.label, style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        if (showLegend) const SizedBox(height: 8),
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: data.map((d) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: double.infinity,
                        height: (d.value / max) * (height - 20),
                        decoration: BoxDecoration(
                          color: d.color,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        d.label,
                        style: TextStyle(fontSize: 9, color: AppColors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color c) => Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

class AppBarData {
  final String label;
  final double value;
  final Color color;
  AppBarData({required this.label, required this.value, required this.color});
}

class AppListTile extends StatefulWidget {
  final String? leadingText;
  final Widget? leadingAvatar;
  final Color? statusDot;
  final String title;
  final String? subtitle;
  final String? trailing;
  final Widget? trailingWidget;
  final Widget? badge;
  final List<Widget>? hoverActions;
  final VoidCallback? onTap;
  final bool isSelected;

  const AppListTile({
    super.key,
    this.leadingText,
    this.leadingAvatar,
    this.statusDot,
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingWidget,
    this.badge,
    this.hoverActions,
    this.onTap,
    this.isSelected = false,
  });

  @override
  State<AppListTile> createState() => _AppListTileState();
}

class _AppListTileState extends State<AppListTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    Widget? leadingWidget;
    if (widget.leadingAvatar != null) {
      leadingWidget = widget.leadingAvatar;
    } else if (widget.leadingText != null) {
      leadingWidget = Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.borderLight,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            widget.leadingText!,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected ? AppColors.bgLight : (_hovered ? AppColors.bgLight : Colors.transparent),
            border: Border(bottom: BorderSide(color: AppColors.borderLight)),
          ),
          child: Row(
            children: [
              if (widget.statusDot != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: widget.statusDot,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (leadingWidget != null) ...[
                leadingWidget,
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.subtitle != null)
                      Text(
                        widget.subtitle!,
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (widget.trailing != null || widget.trailingWidget != null) ...[
                const SizedBox(width: 8),
                if (widget.trailingWidget != null)
                  widget.trailingWidget!
                else
                  Text(
                    widget.trailing!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
              if (widget.badge != null) ...[
                const SizedBox(width: 8),
                widget.badge!,
              ],
              if (_hovered && widget.hoverActions != null && widget.hoverActions!.isNotEmpty) ...[
                const SizedBox(width: 8),
                ...widget.hoverActions!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── SPLIT VIEW (desktop) ─────────────────────────────────────────
class AppSplitView extends StatelessWidget {
  final Widget master;
  final Widget detail;
  final double masterWidth;
  final double detailMinWidth;

  const AppSplitView({
    super.key,
    required this.master,
    required this.detail,
    this.masterWidth = 380,
    this.detailMinWidth = 400,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;
    if (isMobile) {
      return master;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: masterWidth,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: AppColors.border)),
          ),
          child: master,
        ),
        Expanded(
          child: Container(
            constraints: BoxConstraints(minWidth: detailMinWidth),
            child: detail,
          ),
        ),
      ],
    );
  }
}

// ─── INFO ROW (key-value) ─────────────────────────────────────────
class AppInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const AppInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 13 : 12,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 14 : 13,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor ?? AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── AMOUNT CELL ──────────────────────────────────────────────────
class AppAmount extends StatelessWidget {
  final double amount;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? color;

  const AppAmount({
    super.key,
    required this.amount,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w700,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      AmountFormat.format(amount),
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color ?? AppColors.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: 0.1,
      ),
    );
  }
}

// ─── DATE FORMATTER ───────────────────────────────────────────────
class AppDate {
  static final _formatter = DateFormat('d MMM yyyy');
  static final _shortFormatter = DateFormat('d MMM');

  static String format(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      return _formatter.format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }

  static String short(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      return _shortFormatter.format(DateTime.parse(raw));
    } catch (_) {
      return raw;
    }
  }
}

// ─── EMPTY STATE ──────────────────────────────────────────────────
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.border),
            const SizedBox(height: 12),
            Text(title, style: AppTextStyles.h3),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              AppButton(
                label: actionLabel!,
                icon: Icons.add,
                isPrimary: true,
                onTap: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// DOCUMENT PREVIEW PATTERN — Detail screens that feel premium
// ═══════════════════════════════════════════════════════════════════

// ─── Document Hero ──────────────────────────────────────────────
// The focal point. Large amount + status + number.
class DocumentHero extends StatelessWidget {
  final String docNumber;
  final String docType; // 'Invoice', 'Estimate', etc.
  final double amount;
  final String status;
  final Color? statusColor;
  final String? dueDate;
  final String? issueDate;

  const DocumentHero({
    super.key,
    required this.docNumber,
    required this.docType,
    required this.amount,
    required this.status,
    this.statusColor,
    this.dueDate,
    this.issueDate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: AppRadius.card,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: doc type + number + status
          Row(
            children: [
              Text(
                docType.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              StatusBadge(
                label: status,
                color: statusColor,
                backgroundColor: statusColor?.withValues(alpha: 0.08),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Hero amount
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  AmountFormat.format(amount),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    letterSpacing: 0.1,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Doc number + dates
          Row(
            children: [
              Text(
                '#$docNumber',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              if (issueDate != null) ...[
                const SizedBox(width: 12),
                Text(
                  'Issued: ${AppDate.format(issueDate)}',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
              if (dueDate != null) ...[
                const SizedBox(width: 12),
                Text(
                  'Due: ${AppDate.format(dueDate)}',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Customer Card ────────────────────────────────────────────────
// Rich customer info, not just key-value pairs.
class CustomerCard extends StatelessWidget {
  final String name;
  final String? gstin;
  final String? phone;
  final String? email;
  final String? address;
  final double? outstandingBalance;
  final String? state;

  const CustomerCard({
    super.key,
    required this.name,
    this.gstin,
    this.phone,
    this.email,
    this.address,
    this.outstandingBalance,
    this.state,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Customer'.toUpperCase(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5),
          ),
          const SizedBox(height: 10),
          Text(
            name,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              if (gstin != null && gstin!.isNotEmpty)
                _infoChip('GSTIN', gstin!),
              if (phone != null && phone!.isNotEmpty)
                _infoChip('Phone', phone!),
              if (email != null && email!.isNotEmpty)
                _infoChip('Email', email!),
              if (state != null && state!.isNotEmpty)
                _infoChip('State', state!),
              if (outstandingBalance != null && outstandingBalance! > 0)
                _infoChip('Outstanding', '₹${outstandingBalance!.toStringAsFixed(0)}', isAlert: true),
            ],
          ),
          if (address != null && address!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              address!,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value, {bool isAlert = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.textMuted),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isAlert ? AppColors.warning : AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ─── Item Table (compact) ─────────────────────────────────────────
class ItemTable extends StatelessWidget {
  final List<ItemTableRow> items;

  const ItemTable({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.bgLight,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('Item'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
              ),
              Expanded(
                child: Text('Qty'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5), textAlign: TextAlign.center),
              ),
              Expanded(
                child: Text('Rate'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5), textAlign: TextAlign.right),
              ),
              Expanded(
                child: Text('Amount'.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5), textAlign: TextAlign.right),
              ),
            ],
          ),
        ),
        // Rows
        ...items.map((item) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.borderLight)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                    ),
                    if (item.hsn != null)
                      Text('HSN: ${item.hsn}', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                    if (item.gstRate != null && item.gstRate! > 0)
                      Text('GST ${item.gstRate}%', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                  ],
                ),
              ),
              Expanded(
                child: Text(
                  item.qty,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  item.rate,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFeatures: const [FontFeature.tabularFigures()]),
                  textAlign: TextAlign.right,
                ),
              ),
              Expanded(
                child: Text(
                  item.amount,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }
}

class ItemTableRow {
  final String name;
  final String qty;
  final String rate;
  final String amount;
  final String? hsn;
  final double? gstRate;

  ItemTableRow({
    required this.name,
    required this.qty,
    required this.rate,
    required this.amount,
    this.hsn,
    this.gstRate,
  });
}

// ─── Tax Summary Hero ───────────────────────────────────────────
class TaxSummaryHero extends StatelessWidget {
  final double subtotal;
  final double? cgst;
  final double? sgst;
  final double? igst;
  final double? cess;
  final double? roundOff;
  final double total;
  final String? totalLabel;

  const TaxSummaryHero({
    super.key,
    required this.subtotal,
    this.cgst,
    this.sgst,
    this.igst,
    this.cess,
    this.roundOff,
    required this.total,
    this.totalLabel,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tax Summary'.toUpperCase(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          AppInfoRow(label: 'Subtotal', value: AmountFormat.format(subtotal)),
          if (cgst != null && cgst! > 0) AppInfoRow(label: 'CGST', value: AmountFormat.format(cgst!)),
          if (sgst != null && sgst! > 0) AppInfoRow(label: 'SGST', value: AmountFormat.format(sgst!)),
          if (igst != null && igst! > 0) AppInfoRow(label: 'IGST', value: AmountFormat.format(igst!)),
          if (cess != null && cess! > 0) AppInfoRow(label: 'CESS', value: AmountFormat.format(cess!)),
          if (roundOff != null && roundOff != 0) AppInfoRow(label: 'Round Off', value: AmountFormat.format(roundOff!)),
          const Divider(height: 1),
          const SizedBox(height: 12),
          // Hero Total
          Row(
            children: [
              Text(
                (totalLabel ?? 'Total').toUpperCase(),
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5),
              ),
              const Spacer(),
              Text(
                AmountFormat.format(total),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandNavy,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Status Progression ───────────────────────────────────────────
class StatusProgression extends StatelessWidget {
  final List<String> states;
  final String currentState;
  final Map<String, String>? stateLabels;

  const StatusProgression({
    super.key,
    required this.states,
    required this.currentState,
    this.stateLabels,
  });

  @override
  Widget build(BuildContext context) {
    final currentIndex = states.indexOf(currentState.toUpperCase());

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Status'.toUpperCase(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(states.length, (i) {
              final isActive = i <= currentIndex;
              final isCurrent = i == currentIndex;
              return Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isActive ? AppColors.brandNavy : AppColors.borderLight,
                              shape: BoxShape.circle,
                            ),
                            child: isActive
                                ? Icon(Icons.check, size: 12, color: AppColors.textWhite)
                                : null,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            stateLabels?[states[i]] ?? states[i],
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                              color: isActive ? AppColors.textPrimary : AppColors.textMuted,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (i < states.length - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: i < currentIndex ? AppColors.brandNavy : AppColors.borderLight,
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─── Document Preview Screen ──────────────────────────────────────
// The master layout for all detail/preview screens.
class DocumentPreviewScreen extends StatelessWidget {
  final String appBarTitle;
  final List<Widget>? appBarActions;
  final Widget hero;
  final List<Widget> sections;
  final List<Widget>? actions;
  final bool isLoading;
  final String? loadingMessage;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const DocumentPreviewScreen({
    super.key,
    required this.appBarTitle,
    this.appBarActions,
    required this.hero,
    required this.sections,
    this.actions,
    this.isLoading = false,
    this.loadingMessage,
    this.errorMessage,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    if (isLoading) {
      return Scaffold(
        backgroundColor: AppColors.bgLight,
        appBar: AppBar(title: Text(appBarTitle)),
        body: LoadingState(message: loadingMessage ?? 'Loading...'),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        backgroundColor: AppColors.bgLight,
        appBar: AppBar(title: Text(appBarTitle)),
        body: ErrorState(message: errorMessage!, onRetry: onRetry),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        title: Text(appBarTitle),
        actions: appBarActions,
      ),
      body: isMobile
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hero,
                  const SizedBox(height: 16),
                  ...sections,
                  if (actions != null) ...[
                    const SizedBox(height: 16),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Actions'.toUpperCase(),
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 12),
                          ...actions!,
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        hero,
                        const SizedBox(height: 16),
                        ...sections,
                      ],
                    ),
                  ),
                ),
                if (actions != null)
                  Container(
                    width: 260,
                    margin: const EdgeInsets.only(right: 24, top: 24, bottom: 24),
                    child: AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Actions'.toUpperCase(),
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 12),
                          ...actions!,
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ─── SCREEN PATTERNS ──────────────────────────────────────────────
// These are not widgets but patterns. Use the primitives above.
//
// List Screen Pattern:
//   AppBar + Search + Filters + Insights + List + FAB
//
// Detail Screen Pattern:
//   AppBar + Header Card + Sections + Actions Panel (desktop)
//
// Dashboard Pattern:
//   Header + Snapshot + Actions + Charts + Lists
//
// Document Preview Pattern:
//   DocumentPreviewScreen with Hero + Sections + Actions
//
// ═══════════════════════════════════════════════════════════════════

// ─── NEW WIDGETS FOR REDESIGN v4.1 ──────────────────────────────────

class AppAvatar extends StatelessWidget {
  final String name;
  final double size;
  const AppAvatar({super.key, required this.name, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final cleanName = name.trim();
    String initials = '';
    if (cleanName.isNotEmpty) {
      final parts = cleanName.split(' ');
      if (parts.length > 1) {
        initials = (parts[0][0] + parts[1][0]).toUpperCase();
      } else if (parts[0].isNotEmpty) {
        initials = parts[0].substring(0, parts[0].length > 1 ? 2 : 1).toUpperCase();
      }
    }
    final hash = name.hashCode;
    final colors = [
      const Color(0xFF3B82F6),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFF06B6D4),
    ];
    final color = colors[hash.abs() % colors.length];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

class AppStatBar extends StatelessWidget {
  final String title;
  final double total;
  final double? paid;
  final double? pending;
  const AppStatBar({
    super.key,
    required this.title,
    required this.total,
    this.paid,
    this.pending,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: AppTextStyles.overline,
              ),
              const SizedBox(height: 2),
              Text(
                AmountFormat.format(total),
                style: AppTextStyles.amountLarge.copyWith(color: AppColors.brandNavy),
              ),
            ],
          ),
          if (paid != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'PAID',
                  style: AppTextStyles.overline.copyWith(color: AppColors.success),
                ),
                const SizedBox(height: 2),
                Text(
                  AmountFormat.format(paid!),
                  style: AppTextStyles.amount.copyWith(color: AppColors.success),
                ),
              ],
            ),
          if (pending != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'PENDING',
                  style: AppTextStyles.overline.copyWith(color: AppColors.warning),
                ),
                const SizedBox(height: 2),
                Text(
                  AmountFormat.format(pending!),
                  style: AppTextStyles.amount.copyWith(color: AppColors.warning),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class AppFilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final String? badgeText;

  const AppFilterChip({
    super.key,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.brandNavy : AppColors.bgSurface,
          borderRadius: AppRadius.pillBorder,
          border: Border.all(
            color: isActive ? AppColors.brandNavy : AppColors.borderInput,
            width: 1,
          ),
          boxShadow: isActive ? AppShadows.glow : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTextStyles.tabLabel.copyWith(
                color: isActive ? AppColors.textWhite : AppColors.textSecondary,
              ),
            ),
            if (badgeText != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.goldAccent : AppColors.bgLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badgeText!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppColors.brandNavy : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AppSpeedDialOption {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  AppSpeedDialOption({required this.icon, required this.label, required this.onTap});
}

class AppSpeedDial extends StatefulWidget {
  final List<AppSpeedDialOption> options;
  final IconData mainIcon;
  final IconData activeIcon;
  const AppSpeedDial({
    super.key,
    required this.options,
    this.mainIcon = Icons.add,
    this.activeIcon = Icons.close,
  });

  @override
  State<AppSpeedDial> createState() => _AppSpeedDialState();
}

class _AppSpeedDialState extends State<AppSpeedDial> with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  late AnimationController _controller;
  late Animation<double> _expandAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      value: 0.0,
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.fastOutSlowIn,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_isOpen)
            SizeTransition(
              sizeFactor: _expandAnimation,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: widget.options.map((opt) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10, right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Material(
                            color: AppColors.brandNavy,
                            borderRadius: BorderRadius.circular(4),
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Text(
                                opt.label,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FloatingActionButton.small(
                          heroTag: opt.label,
                          onPressed: () {
                            _toggle();
                            opt.onTap();
                          },
                          backgroundColor: AppColors.bgSurface,
                          foregroundColor: AppColors.brandNavy,
                          child: Icon(opt.icon),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          FloatingActionButton(
            heroTag: 'main_fab',
            onPressed: _toggle,
            backgroundColor: AppColors.goldAccent,
            child: Icon(_isOpen ? widget.activeIcon : widget.mainIcon),
          ),
        ],
      ),
    );
  }
}

class AppCommandBar extends StatelessWidget {
  final String title;
  final Widget? searchWidget;
  final List<Widget> actions;
  const AppCommandBar({
    super.key,
    required this.title,
    this.searchWidget,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: AppTextStyles.h2.copyWith(color: AppColors.brandNavy),
          ),
          const Spacer(),
          if (searchWidget != null) ...[
            SizedBox(
              width: 300,
              child: searchWidget!,
            ),
            const SizedBox(width: 16),
          ],
          ...actions,
        ],
      ),
    );
  }
}

class AppStatusTabBar extends StatelessWidget {
  final List<String> tabs;
  final String activeTab;
  final ValueChanged<String> onTabChanged;
  final Map<String, int>? badges;

  const AppStatusTabBar({
    super.key,
    required this.tabs,
    required this.activeTab,
    required this.onTabChanged,
    this.badges,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isActive = tab.toUpperCase() == activeTab.toUpperCase();
          final badgeCount = badges?[tab];
          return Center(
            child: AppFilterChip(
              label: tab,
              isActive: isActive,
              onTap: () => onTabChanged(tab),
              badgeText: badgeCount != null ? badgeCount.toString() : null,
            ),
          );
        },
      ),
    );
  }
}

class AppCheckboxCell extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  const AppCheckboxCell({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Center(
        child: Checkbox(
          value: value,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class AppInlineStatus extends StatelessWidget {
  final String status;
  const AppInlineStatus({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status.toUpperCase()) {
      case 'PAID':
      case 'SUCCESS':
      case 'ACCEPTED':
        color = AppColors.success;
        break;
      case 'DRAFT':
        color = AppColors.textMuted;
        break;
      case 'OVERDUE':
      case 'CANCELLED':
      case 'DECLINED':
      case 'FAILED':
        color = AppColors.error;
        break;
      case 'PENDING':
      case 'PARTIALLY_PAID':
      case 'SENT':
        color = AppColors.warning;
        break;
      default:
        color = AppColors.textSecondary;
    }

    return Text(
      status.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.3,
      ),
    );
  }
}

class AppRowActions extends StatelessWidget {
  final List<Widget> children;
  const AppRowActions({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class AppLinkedDocChip extends StatelessWidget {
  final String docNumber;
  final VoidCallback? onTap;
  const AppLinkedDocChip({super.key, required this.docNumber, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.accentBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.accentBlue.withValues(alpha: 0.2)),
        ),
        child: Text(
          docNumber,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.accentBlue,
          ),
        ),
      ),
    );
  }
}

class AppStickyBottomBar extends StatelessWidget {
  final List<Widget> children;
  const AppStickyBottomBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: children,
        ),
      ),
    );
  }
}
