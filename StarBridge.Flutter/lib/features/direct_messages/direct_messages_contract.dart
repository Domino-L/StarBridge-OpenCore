import '../communities/community_invitation_attachment.dart';
import '../common/chat_room_invitation.dart';
import 'direct_message_receive_polling.dart';
export 'direct_message_read_scope.dart';

String? conversationPresence(String state, Object? value) =>
    state == 'friend' &&
        const {'online', 'away', 'inGame', 'offline'}.contains(value)
    ? value as String
    : null;

final class Conversation {
  const Conversation(
    this.ref,
    this.name,
    this.preview,
    this.time,
    this.unread,
    this.state, {
    this.avatar,
    this.conversationKey,
    this.gameId = '',
    this.presence,
  });
  final String ref, name, preview, state;
  final String? avatar;
  final String? conversationKey;
  final String gameId;
  final String? presence;
  final DateTime time;
  final int unread;
  bool get request =>
      state == 'request_incoming' || state == 'request_outgoing';
  Conversation withoutPresence() => presence == null
      ? this
      : Conversation(
          ref,
          name,
          preview,
          time,
          unread,
          state,
          avatar: avatar,
          conversationKey: conversationKey,
          gameId: gameId,
        );
}

final class DirectMessage {
  const DirectMessage(
    this.sequence,
    this.id,
    this.incoming,
    this.text,
    this.time,
    this.attachment, {
    this.communityInvitation,
    this.roomInvitation,
  });
  final int sequence;
  final String id, text;
  final bool incoming;
  final DateTime time;
  final String? attachment;
  final CommunityInvitationAttachment? communityInvitation;
  final ChatRoomInvitation? roomInvitation;
}

final class DirectPage {
  const DirectPage(
    this.ref,
    this.messages,
    this.oldest,
    this.latest,
    this.hasOlder,
    this.state, {
    this.canSend = false,
    this.localHistoryUnavailable = false,
  });
  final String ref, state;
  final List<DirectMessage> messages;
  final int oldest, latest;
  final bool hasOlder;
  final bool canSend;
  final bool localHistoryUnavailable;
}

final class DirectSendResult {
  const DirectSendResult(this.status, {this.error, this.message});
  final String status;
  final String? error;
  final DirectMessage? message;
}

/// A receipt alone is insufficient: it must identify this exact outgoing text.
bool confirmedDirectSend(DirectSendResult result, String id, String text) {
  final message = result.message;
  return const {'sent', 'duplicate', 'request_sent'}.contains(result.status) &&
      message != null &&
      message.id == id &&
      !message.incoming &&
      message.text == text &&
      message.sequence > 0 &&
      message.attachment == null;
}

abstract interface class DirectMessageSender {
  bool get supportsSending;
  Future<DirectSendResult> send(
    String ref,
    String text,
    String clientMessageId,
  );
}

abstract interface class DirectMessagesPort {
  Stream<void> get invalidations;
  Future<List<Conversation>> directory();
  Future<DirectPage> history(String ref, {int before = 0, int after = 0});
  void cancel();
  Future<void> close();
}

/// Published directory updates are read-only. Explicit refresh/initial reads
/// still call directory() and join a fresh owner read.
abstract interface class DirectMessageDirectoryUpdatesPort {
  Future<List<Conversation>> receiveDirectory();
}

abstract interface class DirectMessageReceptionPort {
  DirectMessageReceiveLease observeVisibleReception(bool Function() visible);
}

abstract interface class DirectMessageActivityPort {
  Stream<void> get changes;
}

/// A changed directory was read for another conversation's hint: refresh the
/// visible list without pulling the open conversation's history.
abstract interface class DirectMessageDirectoryActivityPort {
  Stream<void> get directoryChanges;
}

/// Opaque Host-issued targets. Empty means directory reconciliation only.
abstract interface class DirectMessageHintPort {
  Stream<List<String>> get hints;
}

abstract interface class DirectMessageActivityHealthPort {
  bool get activityHealthy;
}

/// Receive scheduling needs DM push support, independently of the existing
/// connection notice/send recovery health (which also accepts HTTP activity).
abstract interface class DirectMessagePushHealthPort {
  bool get pushHealthy;
}

bool directMessageReceptionHealthy(DirectMessagesPort port) =>
    port is DirectMessagePushHealthPort
    ? (port as DirectMessagePushHealthPort).pushHealthy
    : port is DirectMessageActivityHealthPort &&
          (port as DirectMessageActivityHealthPort).activityHealthy;

final class DirectReadReceipt {
  const DirectReadReceipt(this.through, this.unread);
  final int through, unread;
}

abstract interface class DirectReadReceiptPort {
  bool get supportsReadReceipts;
  Future<DirectReadReceipt> markRead(String ref, int through);
}

abstract interface class DirectViewerAvatarPort {
  String? get viewerAvatar;
}

final class DirectReadFailure implements Exception {
  const DirectReadFailure(this.code);
  final String code;
}

final class UnavailableDirectMessages implements DirectMessagesPort {
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<List<Conversation>> directory() async =>
      throw const DirectReadFailure('unavailable');
  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async => throw const DirectReadFailure('unavailable');
  @override
  void cancel() {}
  @override
  Future<void> close() async {}
}
