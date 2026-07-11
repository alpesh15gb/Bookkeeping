/// Feature flags. Defined centrally so modules can gate experimental UI and
/// roll out behavior without code changes. Flags default to `false` unless
/// explicitly enabled; an owner override can flip them at runtime.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Known feature flag keys.
class FeatureFlags {
  FeatureFlags._();

  // Add flags here as modules grow. Examples:
  static const commandPalette = 'command_palette';
  static const appTour = 'app_tour';
  static const favorites = 'favorites';
  static const recentItems = 'recent_items';
  static const ocrScanning = 'ocr_scanning';
  static const eInvoicing = 'e_invoicing';
}

/// Provider exposing the current flag map. Defaults are conservative; the
/// bootstrap can override with remote-config values.
final featureFlagsProvider = StateProvider<Map<String, bool>>(
  (ref) => const {
    FeatureFlags.commandPalette: true,
    FeatureFlags.recentItems: true,
    FeatureFlags.favorites: true,
    FeatureFlags.appTour: false,
    FeatureFlags.ocrScanning: false,
    FeatureFlags.eInvoicing: false,
  },
);

/// `true` when [flag] is enabled.
bool isEnabled(WidgetRef ref, String flag) =>
    ref.read(featureFlagsProvider)[flag] ?? false;

/// Toggles a flag at runtime.
void toggleFlag(WidgetRef ref, String flag, {required bool enabled}) {
  ref.read(featureFlagsProvider.notifier).update((m) => {...m, flag: enabled});
}
