import '../../app/feature_registry.dart';
import '../../design_system/surfaces/light_visual_shadow_scope.dart';
import 'communities_module.dart';
import 'communities_page.dart';
import 'community_shortcuts.dart';
import '../settings/bridge_notification_sources.dart';
import '../settings/local_privacy_controller.dart';
import '../settings/local_privacy_port.dart';
import '../settings/organization_personal_settings.dart';
import '../settings/organization_notification_leave_guard.dart';

final communitiesFeature = createCommunitiesFeature();
FeatureDescriptor createCommunitiesFeature({
  CommunitiesPort Function()? createPort,
  CommunitiesModule? module,
  LocalPrivacyPort Function()? createAdmissionPrivacy,
  LocalPrivacyController? privacy,
  NotificationSourcesPort Function()? notificationSources,
}) => FeatureDescriptor(
  id: 'communities',
  route: '/communities',
  labelKey: 'navigation.communities',
  descriptionKey: 'navigation.communities.description',
  icon: StarBridgeIconSemantic.community,
  navigationRegion: NavigationRegion.primary,
  order: 50,
  onPrimaryNavigation: module?.openDiscovery,
  prefetch: module?.prefetch,
  primaryNavigationSelected: module?.primaryNavigationSelected,
  confirmLeave: (_) async {
    if (!await confirmOrganizationNotificationLeave()) return false;
    return await module?.confirmLeave() ?? true;
  },
  buildNavigationPanel: module == null
      ? null
      : (context, iconOnly, selected, activate) => CommunityShortcuts(
          module: module,
          iconOnly: iconOnly,
          selected: selected,
          activate: activate,
        ),
  buildDestination: (_) => OrganizationPersonalSettings(
    privacy: privacy,
    notificationSources: notificationSources,
    // While a game runs (performance mode), fading names are cut with an
    // ellipsis and tooltips drop their shadow, as on the fleet and trading hall.
    child: LightVisualShadowScope(
      child: CommunitiesPage(
        createPort: createPort ?? UnavailableCommunities.new,
        module: module,
        createAdmissionPrivacy: createAdmissionPrivacy,
      ),
    ),
  ),
);
