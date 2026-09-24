import '../../app/feature_registry.dart';
import '../../app/routing/deferred_destination.dart';

final toolsFeature = FeatureDescriptor(
  id: 'tools',
  route: '/tools',
  labelKey: 'navigation.tools',
  descriptionKey: 'navigation.tools.description',
  icon: StarBridgeIconSemantic.tools,
  navigationRegion: NavigationRegion.personal,
  order: 30,
  buildDestination: (_) => const DeferredDestination(
    destinationKey: 'tools',
    icon: StarBridgeIconSemantic.tools,
    bodyKey: 'deferredFeature.tools.body',
  ),
);
