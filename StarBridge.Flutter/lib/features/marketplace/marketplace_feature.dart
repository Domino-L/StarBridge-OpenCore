import '../../app/feature_registry.dart';

final marketplaceFeature = FeatureDescriptor(
  id: 'marketplace',
  route: '/marketplace',
  labelKey: 'navigation.marketplace',
  descriptionKey: 'navigation.marketplace.description',
  icon: StarBridgeIconSemantic.marketplace,
  navigationRegion: NavigationRegion.primary,
  order: 40,
  availability: FeatureAvailability.comingSoon,
);
