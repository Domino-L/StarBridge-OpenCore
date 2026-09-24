import '../../design_system/icons/icon_semantic.dart';

const visibleSettingsSections = <SettingsSection>[
  SettingsSection.accountIdentity,
  SettingsSection.generalData,
  SettingsSection.syncPrivacy,
  SettingsSection.notifications,
  SettingsSection.diagnostics,
  SettingsSection.aboutLegal,
];

enum SettingsSection {
  accountIdentity(
    labelKey: 'settings.accountIdentity',
    descriptionKey: 'settings.accountIdentity.description',
    icon: StarBridgeIconSemantic.account,
  ),
  generalData(
    labelKey: 'settings.generalData',
    descriptionKey: 'settings.generalData.description',
    icon: StarBridgeIconSemantic.generalData,
  ),
  syncPrivacy(
    labelKey: 'settings.syncPrivacy',
    descriptionKey: 'settings.syncPrivacy.description',
    icon: StarBridgeIconSemantic.privacy,
  ),
  notifications(
    labelKey: 'settings.notifications',
    descriptionKey: 'settings.notifications.description',
    icon: StarBridgeIconSemantic.reminder,
  ),
  diagnostics(
    labelKey: 'settings.diagnostics',
    descriptionKey: 'settings.diagnostics.description',
    icon: StarBridgeIconSemantic.diagnostics,
  ),
  aboutLegal(
    labelKey: 'settings.aboutLegal',
    descriptionKey: 'settings.aboutLegal.description',
    icon: StarBridgeIconSemantic.legalNotice,
  );

  const SettingsSection({
    required this.labelKey,
    required this.descriptionKey,
    required this.icon,
  });

  final String labelKey;
  final String descriptionKey;
  final StarBridgeIconSemantic icon;
}
