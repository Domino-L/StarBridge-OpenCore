import '../../features/account/account_models.dart';
import '../../features/account/account_module.dart';
import '../../features/communities/communities_module.dart';
import '../../features/friends/bridge_friends_adapter.dart';
import '../../features/friends/friends_module.dart';
import '../../features/party_rooms/party_rooms_module.dart';
import '../../features/settings/bridge_notification_settings_adapter.dart';
import '../../features/settings/notification_settings_module.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/window/menu_attention.dart';
import '../localization/app_strings.dart';
import '../menu_overlay/menu_friends_session.dart';
import '../preferences/app_preferences_port.dart';
import '../presence/manual_presence.dart';
import 'direct_message_refresh.dart';
import 'menu_social_notice_source.dart';

/// These factories borrow the composition's existing owners. Call them at the
/// original lazy menu-lease seam, not while late composition fields initialize.
MenuSocialNoticeSource composeMenuNotices({
  required BridgeNotificationSettingsAdapter port,
  required NotificationSettingsModule settings,
  required AccountModule account,
  required AppPreferencesPort preferences,
  required BridgeClientSession? session,
}) {
  final generation = account.projection.value.generation;
  return MenuSocialNoticeSource(
    events: port.reminders,
    settings: settings.projection,
    authorization: account.projection,
    invalidations: session?.events
        .where(
          (event) =>
              event.name == 'account.changed' ||
              event.name == 'bootstrap.invalidated',
        )
        .map((_) {}),
    isCurrent: () {
      final current = account.projection.value;
      return current.generation == generation &&
          current.generation == session?.activeGeneration &&
          (current.isSignedIn ||
              current.sessionState == AccountSessionState.legacySignedIn);
    },
    strings: () =>
        AppStrings.resolve(preferences.projection.value.effective.locale),
  );
}

MenuAttentionSource composeMenuAttention({
  required AccountModule account,
  required FriendsModule friends,
  required DirectMessageRefresh? messages,
  required PartyRoomsModule rooms,
  required CommunitiesModule communities,
  required BridgeClientSession? session,
}) {
  final generation = account.projection.value.generation;
  return MenuAttentionSource(
    changes: [
      account.projection,
      friends.incomingAttention,
      if (messages != null) messages.unread,
      rooms.activityCount,
      communities.chatAttention,
    ],
    isCurrent: () {
      final current = account.projection.value;
      return current.generation == generation &&
          current.generation == session?.activeGeneration &&
          (current.isSignedIn ||
              current.sessionState == AccountSessionState.legacySignedIn);
    },
    invalidations: session?.events
        .where(
          (event) =>
              event.name == 'account.changed' ||
              event.name == 'bootstrap.invalidated',
        )
        .map((_) {}),
    read: () => MenuAttention(
      friends: friends.incomingAttention.value,
      comms: messages?.unread.value ?? 0,
      rooms: rooms.activityCount.value,
      organizations: communities.chatAttention.totalCount,
    ),
  );
}

({String contextLabel, String returnLabel, String settingsLabel})
composeMenuLabels(AppPreferencesPort preferences) {
  final strings = AppStrings.resolve(
    preferences.projection.value.effective.locale,
  );
  return (
    contextLabel: strings.text('overlay.sections.menu'),
    returnLabel: strings.text('overlay.menu.return'),
    settingsLabel: strings.text('overlay.sections.menu'),
  );
}

MenuFriendsSession composeMenuFriendsSession({
  required BridgeClientSession? session,
  required AccountModule account,
  required ManualPresenceController? presence,
  required void Function(Map<String, Object?>) publish,
}) => MenuFriendsSession(
  session == null ? UnavailableFriendsPort() : BridgeFriendsAdapter(session),
  publish,
  presence: presence,
  identityChanges: account.projection,
  identity: () {
    final current = account.projection.value;
    if (current.generation != session?.activeGeneration ||
        !(current.isSignedIn ||
            current.sessionState == AccountSessionState.legacySignedIn)) {
      return null;
    }
    return (
      name:
          current.profile?.displayName ??
          current.identity.authoritativeHandle ??
          '',
      handle: current.identity.authoritativeHandle ?? '',
      avatar: current.profile?.avatarImageData,
    );
  },
);
