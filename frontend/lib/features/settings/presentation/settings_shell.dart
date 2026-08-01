/// Settings shell — category-based sidebar navigation instead of flat tabs.
///
/// Categories: Company (Company, FY, Team, Series, GST),
/// Documents (Templates, Printing), Preferences (Regional, Backup),
/// Master Data (Banking, Categories, Taxes, Terms).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apexbooks/core/theme/app_colors.dart';
import 'package:apexbooks/core/theme/responsive.dart';

import '../../masters/banking_profiles/presentation/banking_profile_list_screen.dart';
import '../../masters/expense_categories/presentation/expense_category_list_screen.dart';
import '../../masters/payment_terms/presentation/payment_term_list_screen.dart';
import '../../masters/tax_templates/presentation/tax_template_list_screen.dart';
import 'settings_backup_screen.dart';
import 'settings_company_screen.dart';
import 'settings_financial_year_screen.dart';
import 'settings_gst_config_screen.dart';
import 'settings_invoice_series_screen.dart';
import 'settings_preferences_screen.dart';
import 'settings_document_screen.dart';
import 'settings_team_screen.dart';

// ── Navigation model ──────────────────────────────────────────────────────

class _SettingsEntry {
  const _SettingsEntry(this.label, this.icon, this.screen);
  final String label;
  final IconData icon;
  final Widget screen;
}

const _companyGroup = 'Company';
const _documentsGroup = 'Documents';
const _preferencesGroup = 'Preferences';
const _masterDataGroup = 'Master Data';

final _entries = [
  const _SettingsEntry(
    'Company Profile',
    Icons.business_rounded,
    SettingsCompanyScreen(),
  ),
  const _SettingsEntry(
    'Financial Year',
    Icons.calendar_today_rounded,
    SettingsFinancialYearScreen(),
  ),
  const _SettingsEntry('Team', Icons.group_rounded, SettingsTeamScreen()),
  const _SettingsEntry(
    'Invoice Series',
    Icons.numbers_rounded,
    SettingsInvoiceSeriesScreen(),
  ),
  const _SettingsEntry(
    'GST Config',
    Icons.fact_check_rounded,
    SettingsGstConfigScreen(),
  ),
  // Documents
  const _SettingsEntry(
    'Documents & Printing',
    Icons.print_rounded,
    SettingsDocumentScreen(),
  ),
  // Preferences
  const _SettingsEntry(
    'Regional Preferences',
    Icons.settings_rounded,
    SettingsPreferencesScreen(),
  ),
  const _SettingsEntry(
    'Backup & Restore',
    Icons.backup_rounded,
    SettingsBackupScreen(),
  ),
  // Master Data
  const _SettingsEntry(
    'Banking Profiles',
    Icons.account_balance_rounded,
    BankingProfileListScreen(),
  ),
  const _SettingsEntry(
    'Expense Categories',
    Icons.category_rounded,
    ExpenseCategoryListScreen(),
  ),
  const _SettingsEntry(
    'Tax Rates',
    Icons.percent_rounded,
    TaxTemplateListScreen(),
  ),
  const _SettingsEntry(
    'Payment Terms',
    Icons.payment_rounded,
    PaymentTermListScreen(),
  ),
];

const _groupStart = {
  _companyGroup: 0,
  _documentsGroup: 5,
  _preferencesGroup: 6,
  _masterDataGroup: 8,
};

// ── Screen ────────────────────────────────────────────────────────────────

class SettingsShell extends ConsumerStatefulWidget {
  const SettingsShell({super.key});
  @override
  ConsumerState<SettingsShell> createState() => _SettingsShellState();
}

class _SettingsShellState extends ConsumerState<SettingsShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final isMobile = ResponsiveLayout.isMobile(context);
    final screen = _entries[_selectedIndex].screen;

    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          elevation: 0,
          scrolledUnderElevation: 0.5,
        ),
        body: _buildMobileBody(colors),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          // Sidebar navigation
          SizedBox(
            width: 240,
            child: Container(
              color: colors.surfaceMuted,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Settings',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Configure your business',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: _buildNavItems(colors, context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          VerticalDivider(width: 1, color: colors.border),
          Expanded(child: screen),
        ],
      ),
    );
  }

  List<Widget> _buildNavItems(ApexColors colors, BuildContext context) {
    final items = <Widget>[];
    String? lastGroup;
    for (int i = 0; i < _entries.length; i++) {
      // Determine group header
      String? group;
      for (final g in _groupStart.keys) {
        if (_groupStart[g] == i) {
          group = g;
          break;
        }
      }
      if (group != null && group != lastGroup) {
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              group,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: colors.textMuted,
                letterSpacing: 1.1,
              ),
            ),
          ),
        );
        lastGroup = group;
      }
      final active = i == _selectedIndex;
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: InkWell(
            onTap: () => setState(() => _selectedIndex = i),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: active
                    ? colors.primaryContainer.withValues(alpha: 0.3)
                    : null,
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                    color: active ? colors.primary : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _entries[i].icon,
                    size: 18,
                    color: active ? colors.primary : colors.textSecondary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _entries[i].label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active ? colors.textPrimary : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return items;
  }

  Widget _buildMobileBody(ApexColors colors) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        ..._buildMobileSection('Company', _entries.sublist(0, 5), colors),
        ..._buildMobileSection('Documents', _entries.sublist(5, 6), colors),
        ..._buildMobileSection('Preferences', _entries.sublist(6, 8), colors),
        ..._buildMobileSection('Master Data', _entries.sublist(8), colors),
      ],
    );
  }

  List<Widget> _buildMobileSection(
    String title,
    List<_SettingsEntry> items,
    ApexColors colors,
  ) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 11,
            color: colors.textMuted,
            letterSpacing: 1,
          ),
        ),
      ),
      ...items.map(
        (entry) => ListTile(
          leading: Icon(entry.icon, color: colors.primary),
          title: Text(entry.label, style: const TextStyle(fontSize: 14)),
          trailing: const Icon(Icons.chevron_right_rounded, size: 18),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => entry.screen)),
        ),
      ),
    ];
  }
}
