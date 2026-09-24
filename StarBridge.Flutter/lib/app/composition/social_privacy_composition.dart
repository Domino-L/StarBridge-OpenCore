import '../../features/settings/bridge_direct_message_privacy.dart';
import '../../features/settings/bridge_friend_request_privacy.dart';
import '../../features/settings/bridge_recently_played_privacy.dart';
import '../../features/settings/direct_message_privacy_module.dart';
import '../../features/settings/friend_request_privacy_module.dart';
import '../../features/settings/recently_played_privacy_module.dart';
import '../../platform/bridge/bridge_client_session.dart';

final class SocialPrivacyComposition {
  SocialPrivacyComposition.connected(BridgeClientSession session)
    : directMessages = DirectMessagePrivacyModule(
        BridgeDirectMessagePrivacy(session),
      ),
      friendRequests = FriendRequestPrivacyModule(
        BridgeFriendRequestPrivacy(session),
      ),
      recentlyPlayed = RecentlyPlayedPrivacyModule(
        BridgeRecentlyPlayedPrivacy(session),
      );

  final DirectMessagePrivacyModule directMessages;
  final FriendRequestPrivacyModule friendRequests;
  final RecentlyPlayedPrivacyModule recentlyPlayed;

  Future<void> initialize() async {
    await Future.wait([
      directMessages.initialize(),
      friendRequests.initialize(),
      recentlyPlayed.initialize(),
    ]);
  }

  void dispose() {
    directMessages.dispose();
    friendRequests.dispose();
    recentlyPlayed.dispose();
  }
}
