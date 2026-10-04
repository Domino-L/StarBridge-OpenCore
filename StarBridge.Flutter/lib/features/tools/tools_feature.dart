import '../../app/feature_registry.dart';

final toolsFeature = FeatureDescriptor(
  id: 'tools',
  route: '/tools',
  labelKey: 'navigation.tools',
  descriptionKey: 'navigation.tools.description',
  icon: StarBridgeIconSemantic.tools,
  navigationRegion: NavigationRegion.personal,
  order: 30,
  availability: FeatureAvailability.comingSoon,
);
