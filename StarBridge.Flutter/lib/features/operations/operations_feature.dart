import '../../app/feature_registry.dart';
import '../../app/routing/empty_destination.dart';

final operationsFeature = FeatureDescriptor(
  id: 'operations',
  route: '/operations',
  labelKey: 'navigation.operations',
  descriptionKey: 'navigation.operations.description',
  icon: StarBridgeIconSemantic.operation,
  navigationRegion: NavigationRegion.primary,
  order: 20,
  buildDestination: (_) =>
      const EmptyDestination(semanticLabel: 'operations placeholder'),
);
