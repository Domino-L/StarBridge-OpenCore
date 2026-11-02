import '../../platform/window/taskbar_attention_binding.dart';
import '../preferences/app_preferences.dart';
import 'app_composition.dart';
import 'official_fleet_rally_banner.dart';

/// Projects existing unread/work counts; it never marks business data as read.
TaskbarAttentionBinding composeTaskbarAttention(
  AppComposition composition, {
  required TaskbarAttentionScope scope,
  required int? Function() activeGeneration,
}) => TaskbarAttentionBinding(
  scope: scope,
  changes: [
    composition.account.projection,
    composition.preferences.projection,
    composition.friends.incomingAttention,
    if (composition.friendRequestRefresh != null)
      composition.friendRequestRefresh!.count,
    if (composition.directMessageRefresh != null)
      composition.directMessageRefresh!.unread,
    ?composition.directMessageRequests,
    composition.partyRooms.activityCount,
    composition.communities.chatAttention,
    composition.officialFleet.communication.attentionCount,
    composition.notificationInbox.unread,
    composition.notificationInbox.pendingManagement,
    composition.officialFleet.rally,
    composition.notificationSettings.projection,
  ],
  pending: () {
    final current = composition.account.projection.value;
    if (!(current.isSignedIn || current.isLegacyAccount) ||
        current.generation != activeGeneration()) {
      return false;
    }
    return (composition.friendRequestRefresh?.count.value ??
                composition.friends.incomingAttention.value) >
            0 ||
        (composition.directMessageRefresh?.unread.value ?? 0) > 0 ||
        (composition.directMessageRequests?.value ?? 0) > 0 ||
        composition.partyRooms.activityCount.value > 0 ||
        composition.communities.chatAttention.totalCount > 0 ||
        composition.officialFleet.communication.attentionCount.value > 0 ||
        composition.notificationInbox.unread.value > 0 ||
        composition.notificationInbox.pendingManagement.value > 0 ||
        // A rally asking this member to come flashes until answered or over.
        composition.officialFleet.rally.alertPrompt != null &&
            rallyAlertsEnabled(composition) == true;
  },
  reduceMotion: () =>
      composition.preferences.projection.value.effective.motionPreference ==
      MotionPreference.reduce,
);
