/// User preferences settings screen.
///
/// Currency, date format, number format, and theme mode preferences.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/page_header.dart';
import '../../../core/widgets/states.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/theme_controller.dart';
import '../data/models/preferences.dart';
import '../data/settings_repository.dart';
import 'settings_providers.dart';

class SettingsPreferencesScreen extends ConsumerStatefulWidget {
  const SettingsPreferencesScreen({super.key});

  @override
  ConsumerState<SettingsPreferencesScreen> createState() =>
      _SettingsPreferencesScreenState();
}

class _SettingsPreferencesScreenState
    extends ConsumerState<SettingsPreferencesScreen> {
  bool _isSaving = false;
  bool _populated = false;

  String _currency = 'INR';
  String _dateFormat = 'dd MMM yyyy';
  String _numberFormat = 'en_IN';
  String _themeMode = 'system';

  void _initFields(UserPreferences prefs) {
    if (_populated) return;
    _currency = prefs.currency;
    _dateFormat = prefs.dateFormat;
    _numberFormat = prefs.numberFormat;
    _themeMode = prefs.themeMode;
    _populated = true;
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final repo = ref.read(settingsRepositoryProvider);
    final result = await repo.updatePreferences({
      'currency': _currency,
      'date_format': _dateFormat,
      'number_format': _numberFormat,
      'theme_mode': _themeMode,
    });
    setState(() => _isSaving = false);

    if (!mounted) return;
    if (result is Success) {
      // Apply theme immediately to local state
      final themeMode = switch (_themeMode) {
        'light' => ApexThemeMode.light,
        'dark' => ApexThemeMode.dark,
        _ => ApexThemeMode.system,
      };
      await ref.read(themeControllerProvider.notifier).set(themeMode);
      ref.invalidate(userPreferencesProvider);
      ref.read(notificationServiceProvider).success(
        context,
        'Preferences updated.',
        title: 'Saved',
      );
    } else {
      final err = (result as Failure).error;
      ref.read(notificationServiceProvider).error(
        context,
        err.message,
        title: 'Save failed',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = apexColors(context);
    final async = ref.watch(userPreferencesProvider);

    return Scaffold(
      appBar: null,
      body: async.when(
        loading: () => const Center(child: LoadingSpinner(size: 36)),
        error: (err, _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(userPreferencesProvider),
        ),
        data: (prefs) {
          _initFields(prefs);
          return _buildContent(colors);
        },
      ),
    );
  }

  Widget _buildContent(ApexColors colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Preferences',
            subtitle: 'Currency, format, and display settings',
            actions: [
              FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Currency
          ApexCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Regional Formatting',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set your preferred currency and number formats.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _currency,
                  decoration: const InputDecoration(
                    labelText: 'Currency',
                    prefixIcon: Icon(Icons.attach_money_outlined),
                  ),
                  items: CurrencyCodes.labels.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _currency = v);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _numberFormat,
                  decoration: const InputDecoration(
                    labelText: 'Number Format',
                    prefixIcon: Icon(Icons.numbers_outlined),
                  ),
                  items: NumberFormatPresets.labels.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _numberFormat = v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Date Format
          ApexCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Date Format',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose how dates are displayed across the app.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _dateFormat,
                  decoration: const InputDecoration(
                    labelText: 'Date Format',
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  items: DateFormatPresets.labels.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Row(
                            children: [
                              Text(e.value),
                              const SizedBox(width: 8),
                              Text(
                                '(${e.key})',
                                style: TextStyle(
                                  color: colors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _dateFormat = v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Theme
          ApexCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Appearance',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose between light, dark, or system theme.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                _themeOption(
                  colors,
                  value: 'light',
                  icon: Icons.light_mode_outlined,
                  label: 'Light',
                  subtitle: 'Always use light theme',
                ),
                const SizedBox(height: 8),
                _themeOption(
                  colors,
                  value: 'dark',
                  icon: Icons.dark_mode_outlined,
                  label: 'Dark',
                  subtitle: 'Always use dark theme',
                ),
                const SizedBox(height: 8),
                _themeOption(
                  colors,
                  value: 'system',
                  icon: Icons.settings_suggest_outlined,
                  label: 'System',
                  subtitle: 'Follow system settings',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _themeOption(
    ApexColors colors, {
    required String value,
    required IconData icon,
    required String label,
    required String subtitle,
  }) {
    final selected = _themeMode == value;
    return InkWell(
      borderRadius: BorderRadius.circular(ApexRadius.md),
      onTap: () => setState(() => _themeMode = value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.06)
              : colors.surfaceMuted,
          borderRadius: BorderRadius.circular(ApexRadius.md),
          border: Border.all(
            color: selected ? colors.primary : colors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? colors.primary : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded,
                  size: 20, color: colors.primary),
          ],
        ),
      ),
    );
  }
}
