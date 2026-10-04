import 'package:flutter/material.dart';

import '../../features/account/bridge_account_safety.dart';
import '../../features/account/account_safety_dialog.dart';
import '../../features/communities/community_invite_flow.dart';
import '../../features/communities/community_invite_port.dart';
import '../../features/communities/community_invitation_send_dialog.dart';
import '../../features/communities/community_invitation_send_port.dart';
import '../../features/settings/bridge_local_privacy.dart';
import '../../features/direct_messages/direct_messages_module.dart';
import '../../features/common/user_profile_page.dart';
import '../../features/common/user_interaction.dart' show UserTarget;
import '../social_windows/social_window_binding.dart';
import 'app_composition.dart';

/// Composition owns feature wiring; shell only owns guarded navigation.
SocialWindowBinding composeSocialWindow({
  required String kind,
  required AppComposition composition,
  required BuildContext context,
  required Future<void> Function(String) navigate,
  required Future<void> Function(WidgetBuilder) openProfile,
}) => SocialWindowBinding(
  kind: kind,
  preferences: composition.preferences,
  messages: composition.createWindowMessagesPort(),
  inbox: composition.notificationInbox,
  navigate: (route) async {
    if (!context.mounted) return;
    if (route == '/account-safety') {
      await showAccountSafetyDialog(
        context,
        BridgeAccountSafety(composition.notificationInbox.session),
      );
    } else {
      await navigate(route);
    }
  },
  openProfile: kind != 'messages' || composition.userInteractions == null
      ? null
      : (target) async {
          if (!context.mounted) return;
          await openProfile(
            (_) => socialUserProfile(
              composition,
              source: 'conversation',
              reference: target.ref,
              query: target.gameId,
              avatar: target.avatar,
            ),
          );
        },
  openInvite:
      kind == 'messages' && composition.communities.port is CommunityInvitePort
      ? (code) async {
          if (!context.mounted) return;
          final session = composition.notificationInbox.session;
          await openCommunityInvitation(
            context,
            composition.communities,
            code,
            createPrivacy: session == null
                ? null
                : () => BridgeLocalPrivacy(session),
          );
        }
      : null,
  sendInvite:
      kind == 'messages' &&
          composition.communities.port is CommunityInvitationSendPort &&
          (composition.communities.port as CommunityInvitationSendPort)
              .invitationSendingAvailable
      ? (target) async {
          final chat = DirectMessagesModule(
            composition.createWindowMessagesPort(),
          );
          try {
            await chat.openFriend(target);
            if (context.mounted) {
              await sendCommunityInvitationInChat(
                context,
                composition.communities,
                chat,
              );
            }
          } finally {
            chat.dispose();
          }
        }
      : null,
);

Widget socialUserProfile(
  AppComposition composition, {
  required String source,
  required String reference,
  String? query,
  String? avatar,
}) => UserProfilePage(
  port: composition.userInteractions!,
  target: UserTarget(source, reference, query: query ?? ''),
  avatarImageData: avatar,
);

Conversation friendWindowConversation({
  required String reference,
  required String name,
  String? avatar,
  String? stableKey,
  String? presence,
  String? gameId,
}) => Conversation(
  reference,
  name,
  '',
  DateTime.now(),
  0,
  'friend',
  avatar: avatar,
  gameId: gameId ?? '',
  conversationKey: stableKey,
  presence: conversationPresence('friend', presence),
);
