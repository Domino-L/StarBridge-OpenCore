import 'community_chat_port.dart';
import 'community_announcements_port.dart';

/// Optional official identity protocol, independent of content/profile actions.
/// The controller's existing worker is its only read owner.
abstract interface class CommunityAuthorProjectionPort {
  bool get authorIdentitiesAvailable;

  /// Metadata-only retirement. It must not revoke or clear authorized content.
  Stream<void> get authorIdentityChanges;
  Future<CommunityChatPage> readChatAuthors(
    String targetRef, {
    int after = 0,
    int before = 0,
    List<String> observeMessageRefs = const [],
  });
}

/// The open chat's name renewal: one read without the channel read. It carries
/// no unread count or send state, so those stay with the full read.
abstract interface class CommunityChatAuthorRenewalPort {
  bool get chatAuthorRenewalAvailable;
  Future<CommunityChatPage> renewChatAuthors(
    String targetRef, {
    int after = 0,
    List<String> observeMessageRefs = const [],
  });
}

/// The upper screen's chat tile only. Off unless the relay says otherwise, so a
/// missing answer (an older relay, a failed read) never starts these reads.
abstract interface class OrganizationChatPreviewAuthorPort {
  bool get previewAuthorsAvailable;

  /// Names on the tile end. Includes every chat author retirement; the reverse
  /// does not hold, so losing only this feature leaves the chat's names alone.
  Stream<void> get previewAuthorChanges;
  Future<CommunityChatPage> renewPreviewAuthors(
    String targetRef, {
    int after = 0,
    int limit = 8,
    List<String> observeMessageRefs = const [],
  });
}

/// Optional announcement-person reads share the original announcement worker.
/// Chat-only providers do not acquire an unrelated announcement obligation.
abstract interface class CommunityAnnouncementAuthorProjectionPort {
  bool get authorIdentitiesAvailable;
  Stream<void> get authorIdentityChanges;
  Future<CommunityAnnouncementsPage> readAnnouncementAuthors(
    String targetRef, {
    int offset = 0,
    int? expectedRevision,
    List<String> observeAnnouncementRefs = const [],
  });
}

/// Optional typed detail reads, separate from chat-only or page-only providers.
/// The original announcement detail Future remains its only caller/owner.
abstract interface class CommunityAnnouncementAuthorDetailPort {
  bool get authorIdentitiesAvailable;
  Future<Map<String, Object?>> readAnnouncementAuthorDetail(
    String targetRef,
    String announcementRef,
    int offset,
    String? version, {
    String? expectedAuthorIdentityVersion,
    String? expectedEditorIdentityVersion,
  });
}

/// Optional chat-person detail protocol; content remains the original read.
abstract interface class CommunityChatAuthorDetailPort {
  bool get authorIdentitiesAvailable;
  Future<Map<String, Object?>> readChatAuthorDetail(
    String targetRef,
    String messageRef,
    int offset,
    String? version, {
    String? expectedAuthorIdentityVersion,
  });
}
