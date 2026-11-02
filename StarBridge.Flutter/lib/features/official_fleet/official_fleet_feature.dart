import 'package:flutter/widgets.dart';

import '../../app/feature_registry.dart';
import '../../design_system/theme/classic_font_scope.dart';
import '../../platform/window/native_viewport_visibility.dart';
import 'official_fleet_module.dart';
import 'official_fleet_page.dart';
import '../communities/community_ships_port.dart';
import '../common/organization_hangar_sharing.dart';
import '../settings/bridge_notification_sources.dart';
import '../settings/local_privacy_controller.dart';
import '../settings/organization_personal_settings.dart';

FeatureDescriptor createOfficialFleetFeature(
  OfficialFleetModule module, {
  CommunityShipsPort? sharedShipsPort,
  OrganizationHangarSharingPort? hangarSharingPort,
  LocalPrivacyController? privacy,
  NotificationSourcesPort Function()? notificationSources,
  VoidCallback? onPageShown,
}) => FeatureDescriptor(
  id: 'official-fleet',
  route: '/fleet',
  labelKey: 'navigation.officialFleet',
  descriptionKey: 'navigation.officialFleet.description',
  icon: StarBridgeIconSemantic.officialFleet,
  navigationRegion: NavigationRegion.primary,
  order: 10,
  attentionCount: module.communication.attentionCount,
  buildDestination: (_) => _PageShown(
    onShown: () {
      onPageShown?.call();
      module.entered();
    },
    child: ClassicFontScope(
      child: OrganizationPersonalSettings(
        privacy: privacy,
        notificationSources: notificationSources,
        child: OfficialFleetPage(
          module: module,
          sharedShipsPort: sharedShipsPort,
          hangarSharingPort: hangarSharingPort,
          privacy: privacy,
        ),
      ),
    ),
  ),
);

/// Tells the overlay the main fleet page is the one on screen, so "follow the
/// current page" shows the main fleet. Like the organization workspace, only a
/// visible page announces itself, never a prefetched or hidden one.
class _PageShown extends StatelessWidget {
  const _PageShown({required this.onShown, required this.child});
  final VoidCallback onShown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (TickerMode.valuesOf(context).enabled &&
        NativeViewportScope.isActive(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted &&
            TickerMode.valuesOf(context).enabled &&
            NativeViewportScope.isActive(context)) {
          onShown();
        }
      });
    }
    return child;
  }
}
