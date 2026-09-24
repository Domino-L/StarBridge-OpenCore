import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'settings_capability_catalog.dart';
import 'settings_entry_catalog.dart';

typedef SettingsEntryOpener = Future<void> Function(BuildContext context);

/// UI entry overrides only; this never turns catalog IDs into Host commands.
class SettingsEntryOverrides extends InheritedWidget {
  const SettingsEntryOverrides({
    required this.openers,
    required super.child,
    super.key,
  });
  final Map<String, SettingsEntryOpener> openers;
  static Map<String, SettingsEntryOpener> of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SettingsEntryOverrides>()
          ?.openers ??
      const {};
  @override
  bool updateShouldNotify(SettingsEntryOverrides oldWidget) =>
      oldWidget.openers != openers;
}

/// Shared entry presentation only. It neither reads nor writes account/device
/// data. Feature-specific services must be connected before enabling actions.
Future<void> showSettingsCapabilityEntry(
  BuildContext context,
  SettingsCapabilityDefinition capability,
) {
  final opener = SettingsEntryOverrides.of(context)[capability.id];
  if (opener != null) return opener(context);
  return showDialog<void>(
    context: context,
    builder: (_) => SettingsCapabilityEntryDialog(capability: capability),
  );
}

/// Settings and the appearance center can use this same entry. Opening it must
/// never redeem a code, refresh credentials, or apply a skin implicitly.
Future<void> showEntitlementRedemptionEntry(BuildContext context) =>
    showSettingsCapabilityEntry(
      context,
      SettingsCapabilityCatalog.planned.singleWhere(
        (item) => item.id == 'entitlement-redemption',
      ),
    );

class SettingsCapabilityEntryDialog extends StatelessWidget {
  const SettingsCapabilityEntryDialog({required this.capability, super.key});

  final SettingsCapabilityDefinition capability;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    String t(String key) => settingsEntryText(strings, key);
    return AlertDialog(
      key: Key('settings-entry-${capability.id}'),
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(strings.text(capability.titleKey)),
      content: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t('unavailable'),
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: tokens.colors.warning),
            ),
            SizedBox(height: tokens.space.sm),
            Text(t('notice')),
            SizedBox(height: tokens.space.lg),
            Text(t('options'), style: Theme.of(context).textTheme.labelLarge),
            SizedBox(height: tokens.space.sm),
            for (final action in settingsEntryActions[capability.id]!)
              Padding(
                padding: EdgeInsets.only(bottom: tokens.space.sm),
                child: OutlinedButton(
                  key: Key('settings-action-${capability.id}-$action'),
                  onPressed: null,
                  style: OutlinedButton.styleFrom(
                    disabledForegroundColor: tokens.colors.textSecondary,
                    alignment: AlignmentDirectional.centerStart,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  child: Text(t(action)),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('settings-entry-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t('close')),
        ),
      ],
    );
  }
}
