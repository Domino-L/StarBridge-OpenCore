import 'settings_models.dart';

final class SettingsCapabilityDefinition {
  const SettingsCapabilityDefinition({
    required this.id,
    required this.section,
    required this.titleKey,
    required this.descriptionKey,
  });

  final String id;
  final SettingsSection section;
  final String titleKey;
  final String descriptionKey;
}

abstract final class SettingsCapabilityCatalog {
  static const planned = <SettingsCapabilityDefinition>[
    SettingsCapabilityDefinition(
      id: 'source-rules',
      section: SettingsSection.notifications,
      titleKey: 'settings.capability.sourceRules.title',
      descriptionKey: 'settings.capability.sourceRules.description',
    ),
    SettingsCapabilityDefinition(
      id: 'player-activity',
      section: SettingsSection.notifications,
      titleKey: 'settings.capability.playerActivity.title',
      descriptionKey: 'settings.capability.playerActivity.description',
    ),
    SettingsCapabilityDefinition(
      id: 'continuous-play',
      section: SettingsSection.notifications,
      titleKey: 'settings.capability.playReminders.title',
      descriptionKey: 'settings.capability.playReminders.description',
    ),
    SettingsCapabilityDefinition(
      id: 'account-safety',
      section: SettingsSection.accountIdentity,
      titleKey: 'settings.capability.accountSafety.title',
      descriptionKey: 'settings.capability.accountSafety.description',
    ),
    SettingsCapabilityDefinition(
      id: 'local-data-management',
      section: SettingsSection.generalData,
      titleKey: 'settings.capability.localData.title',
      descriptionKey: 'settings.capability.localData.description',
    ),
    SettingsCapabilityDefinition(
      id: 'local-data-storage',
      section: SettingsSection.generalData,
      titleKey: 'settings.capability.dataStorage.title',
      descriptionKey: 'settings.capability.dataStorage.description',
    ),
    SettingsCapabilityDefinition(
      id: 'entitlement-redemption',
      section: SettingsSection.generalData,
      titleKey: 'settings.capability.redemption.title',
      descriptionKey: 'settings.capability.redemption.description',
    ),
    SettingsCapabilityDefinition(
      id: 'application-updates',
      section: SettingsSection.generalData,
      titleKey: 'settings.capability.updates.title',
      descriptionKey: 'settings.capability.updates.description',
    ),
    SettingsCapabilityDefinition(
      id: 'runtime-status',
      section: SettingsSection.diagnostics,
      titleKey: 'settings.capability.runtimeStatus.title',
      descriptionKey: 'settings.capability.runtimeStatus.description',
    ),
    SettingsCapabilityDefinition(
      id: 'local-event-log',
      section: SettingsSection.diagnostics,
      titleKey: 'settings.capability.eventLog.title',
      descriptionKey: 'settings.capability.eventLog.description',
    ),
    SettingsCapabilityDefinition(
      id: 'one-click-diagnostics',
      section: SettingsSection.diagnostics,
      titleKey: 'settings.capability.oneClickDiagnostics.title',
      descriptionKey: 'settings.capability.oneClickDiagnostics.description',
    ),
    SettingsCapabilityDefinition(
      id: 'local-maintenance',
      section: SettingsSection.diagnostics,
      titleKey: 'settings.capability.maintenance.title',
      descriptionKey: 'settings.capability.maintenance.description',
    ),
    SettingsCapabilityDefinition(
      id: 'installation-update-repair',
      section: SettingsSection.diagnostics,
      titleKey: 'settings.capability.installation.title',
      descriptionKey: 'settings.capability.installation.description',
    ),
  ];

  static List<SettingsCapabilityDefinition> plannedFor(
    SettingsSection section,
  ) => planned
      .where((capability) => capability.section == section)
      .toList(growable: false);
}
