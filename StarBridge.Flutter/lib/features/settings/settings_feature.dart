import 'package:flutter/widgets.dart';

import '../../app/feature_registry.dart';
import 'settings_models.dart';
import 'settings_page.dart';
import 'settings_entry_dialog.dart';

typedef SettingsContentBuilder = Widget Function(BuildContext context);

Iterable<FeatureDescriptor> createSettingsFeatures({
  required SettingsContentBuilder accountAndIdentityBuilder,
  required SettingsContentBuilder generalDataBuilder,
  required SettingsContentBuilder syncPrivacyBuilder,
  required SettingsContentBuilder notificationsBuilder,
  SettingsContentBuilder? diagnosticsBuilder,
  SettingsContentBuilder? helpSupportBuilder,
  DestinationLeaveGuard? confirmPrivacyLeave,
  DestinationLeaveGuard? confirmNotificationsLeave,
  Map<String, SettingsEntryOpener> entryOpeners = const {},
}) sync* {
  Future<bool> confirmLeave(BuildContext context) async {
    if (confirmNotificationsLeave != null &&
        !await confirmNotificationsLeave(context)) {
      return false;
    }
    if (!context.mounted) return false;
    return await confirmPrivacyLeave?.call(context) ?? true;
  }

  yield FeatureDescriptor(
    id: 'sharing-settings',
    route: '/settings/privacy',
    labelKey: 'settings.syncPrivacy',
    descriptionKey: 'settings.syncPrivacy.description',
    icon: StarBridgeIconSemantic.privacy,
    navigationRegion: NavigationRegion.shortcut,
    navigationParentId: 'settings',
    order: 0,
    confirmLeave: confirmLeave,
    buildDestination: (_) => SettingsEntryOverrides(
      openers: entryOpeners,
      child: SettingsPage(
        initialSection: SettingsSection.syncPrivacy,
        helpSupportBuilder: helpSupportBuilder,
        accountAndIdentityBuilder: accountAndIdentityBuilder,
        generalDataBuilder: generalDataBuilder,
        syncPrivacyBuilder: syncPrivacyBuilder,
        notificationsBuilder: notificationsBuilder,
        diagnosticsBuilder: diagnosticsBuilder,
        confirmPrivacyLeave: confirmPrivacyLeave,
        confirmNotificationsLeave: confirmNotificationsLeave,
      ),
    ),
  );
  yield FeatureDescriptor(
    id: 'settings',
    route: '/settings',
    labelKey: 'navigation.settings',
    descriptionKey: 'navigation.settings.description',
    icon: StarBridgeIconSemantic.settings,
    navigationRegion: NavigationRegion.personal,
    order: 40,
    confirmLeave: confirmLeave,
    buildDestination: (_) => SettingsEntryOverrides(
      openers: entryOpeners,
      child: SettingsPage(
        initialSection: SettingsSection.generalData,
        helpSupportBuilder: helpSupportBuilder,
        accountAndIdentityBuilder: accountAndIdentityBuilder,
        generalDataBuilder: generalDataBuilder,
        syncPrivacyBuilder: syncPrivacyBuilder,
        notificationsBuilder: notificationsBuilder,
        diagnosticsBuilder: diagnosticsBuilder,
        confirmPrivacyLeave: confirmPrivacyLeave,
        confirmNotificationsLeave: confirmNotificationsLeave,
      ),
    ),
  );
  yield FeatureDescriptor(
    id: 'account-and-identity',
    route: '/settings/account',
    labelKey: 'settings.accountIdentity',
    descriptionKey: 'settings.accountIdentity.description',
    icon: StarBridgeIconSemantic.account,
    navigationRegion: NavigationRegion.accountMenu,
    navigationParentId: 'settings',
    order: 20,
    confirmLeave: confirmLeave,
    buildDestination: (_) => SettingsEntryOverrides(
      openers: entryOpeners,
      child: SettingsPage(
        initialSection: SettingsSection.accountIdentity,
        helpSupportBuilder: helpSupportBuilder,
        accountAndIdentityBuilder: accountAndIdentityBuilder,
        generalDataBuilder: generalDataBuilder,
        syncPrivacyBuilder: syncPrivacyBuilder,
        notificationsBuilder: notificationsBuilder,
        diagnosticsBuilder: diagnosticsBuilder,
        confirmPrivacyLeave: confirmPrivacyLeave,
        confirmNotificationsLeave: confirmNotificationsLeave,
      ),
    ),
  );
}
