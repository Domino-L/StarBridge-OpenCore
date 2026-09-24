import '../../app/feature_registry.dart';
import '../../app/routing/empty_destination.dart';

import 'package:flutter/foundation.dart';

final notificationsFeature = createNotificationsFeature();

FeatureDescriptor createNotificationsFeature({
  DestinationBuilder? buildContent,
  ValueListenable<int>? attentionCount,
}) => FeatureDescriptor(
  id: 'notifications',
  route: '/notifications',
  labelKey: 'navigation.notifications',
  descriptionKey: 'navigation.notifications.description',
  icon: StarBridgeIconSemantic.notifications,
  navigationRegion: NavigationRegion.topBar,
  order: 20,
  attentionCount: attentionCount,
  buildDestination:
      buildContent ??
      (_) => const EmptyDestination(semanticLabel: 'notifications placeholder'),
);
