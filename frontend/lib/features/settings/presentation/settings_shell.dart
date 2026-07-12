/// Settings shell — hub tab widget with all settings screens.
///
/// Tabs: Company, Financial Year, Team, Invoice Series, GST Config,
/// Preferences, Backup, Banking, Categories, Taxes, Terms.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/home_shell_widgets.dart';
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
import 'settings_team_screen.dart';

class SettingsShell extends ConsumerWidget {
  const SettingsShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const HubTabWidget(
      tabs: [
        'Company',
        'Financial Year',
        'Team',
        'Invoice Series',
        'GST Config',
        'Preferences',
        'Backup',
        'Banking',
        'Categories',
        'Taxes',
        'Terms',
      ],
      views: [
        SettingsCompanyScreen(),
        SettingsFinancialYearScreen(),
        SettingsTeamScreen(),
        SettingsInvoiceSeriesScreen(),
        SettingsGstConfigScreen(),
        SettingsPreferencesScreen(),
        SettingsBackupScreen(),
        BankingProfileListScreen(),
        ExpenseCategoryListScreen(),
        TaxTemplateListScreen(),
        PaymentTermListScreen(),
      ],
    );
  }
}
