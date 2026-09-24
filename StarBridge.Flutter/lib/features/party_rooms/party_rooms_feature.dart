import '../../app/feature_registry.dart';

import 'package:flutter/widgets.dart';

import 'party_rooms_module.dart';
import 'party_rooms_page.dart';

FeatureDescriptor createPartyRoomsFeature(
  PartyRoomsModule module, {
  Future<void> Function(BuildContext, String)? openCommunityInvite,
}) => FeatureDescriptor(
  id: 'party-rooms',
  route: '/rooms',
  labelKey: 'navigation.rooms',
  descriptionKey: 'navigation.rooms.description',
  icon: StarBridgeIconSemantic.room,
  navigationRegion: NavigationRegion.primary,
  order: 30,
  attentionCount: module.activityCount,
  prefetch: () => module.refresh(reuseFresh: true),
  buildDestination: (_) =>
      PartyRoomsPage(module: module, openCommunityInvite: openCommunityInvite),
);
