import '../../app/feature_registry.dart';
import 'communities_module.dart';
import 'communities_page.dart';
import 'community_shortcuts.dart';
import '../settings/local_privacy_port.dart';

final communitiesFeature = createCommunitiesFeature();
FeatureDescriptor createCommunitiesFeature({
  CommunitiesPort Function()? createPort,
  CommunitiesModule? module,
  LocalPrivacyPort Function()? createAdmissionPrivacy,
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
  buildDestination: (_) => CommunitiesPage(
    createPort: createPort ?? UnavailableCommunities.new,
    module: module,
    createAdmissionPrivacy: createAdmissionPrivacy,
  ),
);
