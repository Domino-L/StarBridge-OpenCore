import '../../app/feature_registry.dart';

import 'package:flutter/widgets.dart';

import 'friends_module.dart';
import 'friends_page.dart';
import '../direct_messages/direct_messages_module.dart';

final friendsFeature = createFriendsFeature();

FeatureDescriptor createFriendsFeature({
  FriendsPort Function()? createPort,
  FriendsModule? module,
  DirectMessagesPort Function()? createChatPort,
  ValueNotifier<int>? inboxRequests,
  Future<void> Function(BuildContext, String)? openCommunityInvite,
  Future<void> Function(BuildContext, DirectMessagesModule)?
  sendCommunityInvite,
}) => FeatureDescriptor(
  id: 'friends',
  route: '/friends',
  labelKey: 'navigation.friends',
  descriptionKey: 'navigation.friends.description',
  icon: StarBridgeIconSemantic.friends,
  navigationRegion: NavigationRegion.topBar,
  order: 10,
  prefetch: module?.prefetch,
  buildDestination: (_) => FriendsPage(
    createPort: createPort ?? UnavailableFriendsPort.new,
    module: module,
    createChatPort: createChatPort,
    inboxRequests: inboxRequests,
    openCommunityInvite: openCommunityInvite,
    sendCommunityInvite: sendCommunityInvite,
  ),
);
