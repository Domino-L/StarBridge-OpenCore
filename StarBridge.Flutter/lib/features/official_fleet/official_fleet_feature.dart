import '../../app/feature_registry.dart';
import 'official_fleet_module.dart';
import 'official_fleet_page.dart';

FeatureDescriptor createOfficialFleetFeature(OfficialFleetModule module) =>
    FeatureDescriptor(
      id: 'official-fleet',
      route: '/fleet',
      labelKey: 'navigation.officialFleet',
      descriptionKey: 'navigation.officialFleet.description',
      icon: StarBridgeIconSemantic.officialFleet,
      navigationRegion: NavigationRegion.primary,
      order: 10,
      buildDestination: (_) => OfficialFleetPage(module: module),
    );
