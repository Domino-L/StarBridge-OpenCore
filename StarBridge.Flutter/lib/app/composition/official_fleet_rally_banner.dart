import 'package:flutter/widgets.dart';

import '../../features/official_fleet/official_fleet_rally_views.dart';
import '../../features/settings/notification_settings_models.dart';
import 'app_composition.dart';

/// The shell's rally notice: members see a running main-fleet rally on any
/// page, plus one desktop notification per rally.
Widget officialFleetRallyBanner(AppComposition composition) =>
    OfficialFleetRallyNotice(
      controller: composition.officialFleet.rally,
      desktop: composition.desktopNotifications,
      alertsEnabled: () => rallyAlertsEnabled(composition),
      alertsChanged: composition.notificationSettings.projection,
    );

/// The rally alerts switch. Null while it is not known yet (loading, or a read
/// that failed): a saved "off" must never be overtaken by a default.
bool? rallyAlertsEnabled(AppComposition composition) => rallyAlertsDecision(
  composition.notificationSettings.projection.value,
  hostHasSettings:
      composition.firstUseSession?.hostCapabilities.contains(
        'notificationSettings.read',
      ) ==
      true,
);

/// Only a Host that never offered notification settings keeps the old
/// always-on notice; a Host that has them but could not answer (read failed,
/// bridge disconnected) is unknown until it does.
bool? rallyAlertsDecision(
  NotificationSettingsProjection projection, {
  required bool hostHasSettings,
}) => switch (projection.availability) {
  NotificationSettingsAvailability.available =>
    projection.settings?.channels.rallyAlertsEnabled ?? true,
  NotificationSettingsAvailability.loading => null,
  _ => hostHasSettings ? null : true,
};
