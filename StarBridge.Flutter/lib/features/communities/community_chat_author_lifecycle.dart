import 'dart:async';

import 'community_author_projection.dart';
import 'community_author_projection_port.dart';
import 'community_chat_author_window.dart';
import 'community_chat_media_cache.dart';
import 'community_chat_port.dart';
import 'community_chat_seen_authors.dart';

/// Owns author presentation, withdrawal and the original one-shot deadline.
/// Conversation content and IO remain with the chat controller.
final class CommunityChatAuthorLifecycle {
  CommunityChatAuthorLifecycle({
    required this.port,
    required this.clock,
    required this.active,
    required this.allowed,
    required this.messages,
    required this.replaceMessages,
    required this.media,
    required this.onChanged,
    this.elapsed,
  });

  final CommunityChatPort port;
  final DateTime Function() clock;
  final Duration Function()? elapsed;
  final bool Function() active, allowed;
  final List<CommunityChatMessage> Function() messages;
  final void Function(List<CommunityChatMessage>) replaceMessages;
  final CommunityChatMediaCache? Function() media;
  final void Function() onChanged;
  List<CommunityChatMessage> get _messages => messages();
  set _messages(List<CommunityChatMessage> value) => replaceMessages(value);
  CommunityChatMediaCache? get _media => media();

  CommunityChatMessage presentAuthor(CommunityChatMessage message) {
    if (port is! CommunityAuthorProjectionPort) return message;
    if (!(port as CommunityAuthorProjectionPort).authorIdentitiesAvailable) {
      seenAuthors.clear();
      return CommunityChatMessage.neutralAuthor(message);
    }
    return seenAuthors.present(
      message,
      verified: window.canPresent(message.messageRef),
      allowed: active() && allowed(),
      now: identityNow(),
    );
  }

  /// Recheck the owner after media IO; a newer observation renews no older one.
  bool authorIsCurrent(CommunityChatMessage message) {
    if (!active() ||
        !allowed() ||
        port is! CommunityAuthorProjectionPort ||
        !(port as CommunityAuthorProjectionPort).authorIdentitiesAvailable ||
        !window.canPresent(message.messageRef)) {
      return false;
    }
    final current = _messages
        .where((row) => row.messageRef == message.messageRef)
        .firstOrNull;
    final identity = current?.authorIdentity, expected = message.authorIdentity;
    return current?.senderRef == message.senderRef &&
        identity?.visible == true &&
        seenAuthors.allowsProof(message.senderRef, identity!) &&
        identityNow().isBefore(CommunityChatSeenAuthors.deadline(identity)) &&
        identity.admit(identityNow()).visible == true &&
        expected?.visible == true &&
        identity.version == expected!.version &&
        identity.avatarVersion == expected.avatarVersion &&
        identity.observedAt == expected.observedAt &&
        identity.validUntil == expected.validUntil;
  }

  late final window = CommunityChatAuthorWindow(elapsed: elapsed);
  late final seenAuthors = CommunityChatSeenAuthors(
    now: identityNow,
    elapsed: elapsed,
  );
  DateTime identityNow() => window.identityTime(clock());
  Timer? _authorExpiry;
  int _authorExpiryEpoch = 0;
  void cancelExpiry() {
    _authorExpiryEpoch++;
    _authorExpiry?.cancel();
    _authorExpiry = null;
  }

  bool retireProofs(Iterable<CommunityChatMessage> expired) {
    final result = window.retireProofs(_messages, expired);
    _messages = result.messages;
    _media?.retireAuthors(result.retired);
    return result.retired.isNotEmpty;
  }

  void narrowAuthor(
    CommunityChatMessage message,
    CommunityAuthorProjection observed,
  ) {
    if (!active()) return;
    if (observed.visible) {
      if (port is! CommunityAuthorProjectionPort ||
          !(port as CommunityAuthorProjectionPort).authorIdentitiesAvailable ||
          !seenAuthors.canNarrowAvatar(message.senderRef, observed) ||
          _messages.any(
            (row) =>
                row.senderRef == message.senderRef &&
                row.authorIdentity?.visible == true &&
                row.authorIdentity!.observedAt!.isAfter(observed.observedAt!),
          )) {
        return;
      }
      seenAuthors.withdrawAvatar(
        message.senderRef,
        observedAt: observed.observedAt,
      );
      retireProofs(_messages.where((m) => m.senderRef == message.senderRef));
      _media?.retireSenders({message.senderRef});
      scheduleExpiry();
      onChanged();
      return;
    }
    final hidden = observed.state == CommunityAuthorState.hidden;
    if (hidden) {
      withdrawAuthor(message.senderRef);
      scheduleExpiry();
      onChanged();
      return;
    }
    if (!authorIsCurrent(message)) return;
    if (retireProofs([message])) {
      scheduleExpiry();
      onChanged();
    }
  }

  void withdrawAuthor(String sender) {
    seenAuthors.hide(sender);
    retireProofs(_messages.where((m) => m.senderRef == sender));
    _media?.retireSenders({sender});
  }

  /// The original one-shot display deadline remains the only identity Timer.
  void scheduleExpiry() {
    cancelExpiry();
    if (!active() ||
        !allowed() ||
        port is! CommunityAuthorProjectionPort ||
        !(port as CommunityAuthorProjectionPort).authorIdentitiesAvailable) {
      return;
    }
    final now = identityNow();
    seenAuthors.sweep(at: now);
    DateTime? earliest = _media?.nextAuthorDeadline;
    for (final message in _messages) {
      if (!window.canPresent(message.messageRef)) continue;
      final identity = message.authorIdentity;
      final deadline = identity?.visible == true
          ? CommunityChatSeenAuthors.deadline(identity!)
          : null;
      if (deadline != null &&
          deadline.isAfter(now) &&
          (earliest == null || deadline.isBefore(earliest))) {
        earliest = deadline;
      }
    }
    final seenDelay = seenAuthors.nextRetirement;
    if (seenDelay != null) {
      final deadline = now.add(seenDelay);
      if (earliest == null || deadline.isBefore(earliest)) earliest = deadline;
    }
    if (earliest == null) return;
    final deadline = earliest, captured = _authorExpiryEpoch;
    _authorExpiry = Timer(deadline.difference(now), () {
      if (!active() || captured != _authorExpiryEpoch) return;
      _authorExpiry = null;
      final at = window.identityTime(clock(), reachedDeadline: deadline);
      seenAuthors.sweep(at: at);
      retireProofs([
        ..._messages.where(
          (message) =>
              message.authorIdentity?.visible == true &&
              !CommunityChatSeenAuthors.deadline(message.authorIdentity!)
                  .isAfter(at),
        ),
        ...?_media?.retireExpiredAuthors(at),
      ]);
      onChanged();
      scheduleExpiry();
    });
  }

  void retireAuthors({bool notify = false}) {
    if (port is! CommunityAuthorProjectionPort) return;
    cancelExpiry();
    _media?.retireAuthors(_messages);
    window.retire();
    scheduleExpiry();
    if (notify && active()) onChanged();
  }
}
