import 'package:flutter/widgets.dart';

import 'bridge_notification_sources.dart';
import 'local_privacy_controller.dart';

/// The viewer's own settings for one organization, for pages that show them
/// beside its management (user 2026-10-31). Without a host there are none, and
/// the pages simply leave these sections out.
class OrganizationPersonalSettings extends InheritedWidget {
  const OrganizationPersonalSettings({
    required this.privacy,
    required this.notificationSources,
    required super.child,
    super.key,
  });

  final LocalPrivacyController? privacy;
  final NotificationSourcesPort Function()? notificationSources;

  static OrganizationPersonalSettings? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OrganizationPersonalSettings>();

  @override
  bool updateShouldNotify(OrganizationPersonalSettings oldWidget) =>
      !identical(privacy, oldWidget.privacy) ||
      !identical(notificationSources, oldWidget.notificationSources);
}
