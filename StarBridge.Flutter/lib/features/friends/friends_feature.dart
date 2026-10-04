import '../../app/feature_registry.dart';

import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

import 'friends_module.dart';
import 'friends_page.dart';
import '../direct_messages/direct_messages_module.dart';

final friendsFeature = createFriendsFeature();

FeatureDescriptor createFriendsFeature({
  bool messagesOnly = false,
  bool separateMessages = false,
  FriendsPort Function()? createPort,
  FriendsModule? module,
  DirectMessagesPort Function()? createChatPort,
  ValueNotifier<int>? inboxRequests,
  ValueListenable<int>? attentionCount,
  Future<void> Function(BuildContext, String)? openCommunityInvite,
  Future<void> Function(BuildContext, DirectMessagesModule)?
  sendCommunityInvite,
}) => FeatureDescriptor(
  id: messagesOnly ? 'messages' : 'friends',
  route: messagesOnly ? '/messages' : '/friends',
  labelKey: messagesOnly ? 'navigation.messages' : 'navigation.friends',
  descriptionKey: messagesOnly ? 'navigation.messages.description' : 'navigation.friends.description',
  icon: messagesOnly ? StarBridgeIconSemantic.messages : StarBridgeIconSemantic.friends,
  navigationRegion: NavigationRegion.topBar,
  order: messagesOnly ? 9 : 10,
  attentionCount: attentionCount,
  prefetch: module?.prefetch,
  buildDestination: (_) => FriendsPage(
    messagesOnly: messagesOnly,
    separateMessages: separateMessages,
    createPort: createPort ?? UnavailableFriendsPort.new,
    module: module,
    createChatPort: createChatPort,
    inboxRequests: inboxRequests,
    openCommunityInvite: openCommunityInvite,
    sendCommunityInvite: sendCommunityInvite,
  ),
);
