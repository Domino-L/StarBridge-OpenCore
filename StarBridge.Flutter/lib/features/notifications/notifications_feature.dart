import '../../app/feature_registry.dart';

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
  availability: buildContent == null
      ? FeatureAvailability.comingSoon
      : FeatureAvailability.available,
  buildDestination: buildContent,
);
