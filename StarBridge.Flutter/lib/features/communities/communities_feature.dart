import '../../app/feature_registry.dart';
import 'communities_module.dart';
import 'communities_page.dart';
import 'community_shortcuts.dart';
import '../settings/bridge_notification_sources.dart';
import '../settings/local_privacy_controller.dart';
import '../settings/local_privacy_port.dart';
import '../settings/organization_personal_settings.dart';

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
  confirmLeave: module == null ? null : (_) => module.confirmLeave(),
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
    child: CommunitiesPage(
      createPort: createPort ?? UnavailableCommunities.new,
      module: module,
      createAdmissionPrivacy: createAdmissionPrivacy,
    ),
  ),
);
