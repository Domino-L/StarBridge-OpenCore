import '../../app/feature_registry.dart';
import '../../app/routing/deferred_destination.dart';

final marketplaceFeature = FeatureDescriptor(
  id: 'marketplace',
  route: '/marketplace',
  labelKey: 'navigation.marketplace',
  descriptionKey: 'navigation.marketplace.description',
  icon: StarBridgeIconSemantic.marketplace,
  navigationRegion: NavigationRegion.primary,
  order: 40,
  buildDestination: (_) => const DeferredDestination(
    destinationKey: 'marketplace',
    icon: StarBridgeIconSemantic.marketplace,
    bodyKey: 'deferredFeature.marketplace.body',
  ),
);
