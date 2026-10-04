import '../../app/feature_registry.dart';

final operationsFeature = FeatureDescriptor(
  id: 'operations',
  route: '/operations',
  labelKey: 'navigation.operations',
  descriptionKey: 'navigation.operations.description',
  icon: StarBridgeIconSemantic.operation,
  navigationRegion: NavigationRegion.primary,
  order: 20,
  availability: FeatureAvailability.comingSoon,
);
