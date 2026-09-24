import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/settings/settings_capability_catalog.dart';
import 'package:starbridge_flutter/features/settings/settings_models.dart';

void main() {
  test(
    'planned settings catalog retains WPF capabilities without duplicates',
    () {
      final capabilities = SettingsCapabilityCatalog.planned;
      final ids = capabilities.map((capability) => capability.id).toList();

      expect(ids.toSet(), hasLength(ids.length));
      expect(ids, isNot(contains('local-game-recognition')));
      expect(
        ids,
        containsAll(<String>[
          'account-safety',
          'local-data-management',
          'local-data-storage',
          'entitlement-redemption',
          'application-updates',
          'runtime-status',
          'local-event-log',
          'one-click-diagnostics',
          'local-maintenance',
          'installation-update-repair',
        ]),
      );
      expect(
        ids,
        isNot(contains('gameplay-statistics')),
        reason: 'Gameplay time is now a working settings panel, not a planned placeholder.',
      );
      expect(
        capabilities.where(
          (capability) =>
              capability.id.contains('location-code-contribution') ||
              capability.id.contains('location-data-contribution'),
        ),
        isEmpty,
      );
      for (final section in <SettingsSection>[
        SettingsSection.accountIdentity,
        SettingsSection.generalData,
        SettingsSection.diagnostics,
      ]) {
        expect(SettingsCapabilityCatalog.plannedFor(section), isNotEmpty);
      }
      expect(
        SettingsCapabilityCatalog.plannedFor(SettingsSection.aboutLegal),
        isEmpty,
      );
      expect(
        SettingsCapabilityCatalog.plannedFor(SettingsSection.syncPrivacy),
        isEmpty,
      );
      expect(
        SettingsCapabilityCatalog.plannedFor(SettingsSection.notifications),
        hasLength(3),
      );
    },
  );

  test('every retained capability has copy in all supported languages', () {
    for (final locale in const <Locale>[
      Locale('zh', 'CN'),
      Locale('zh', 'TW'),
      Locale('en', 'US'),
    ]) {
      final strings = AppStrings.resolve(locale);
      for (final capability in SettingsCapabilityCatalog.planned) {
        expect(strings.text(capability.titleKey), isNot(capability.titleKey));
        expect(
          strings.text(capability.descriptionKey),
          isNot(capability.descriptionKey),
        );
      }
    }
  });
}
