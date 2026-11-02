import 'community_chat_port.dart';
import 'community_author_projection.dart';

typedef CommunityChatReferenceRecovery = ({
  int epoch,
  int before,
  List<CommunityChatMessage> messages,
});

/// Presentation residency only. No timers, persistence, network or receipts.
final class CommunityChatAuthorWindow {
  DateTime? _identityFloor;

  /// Conservative local display time, not a new server observation or lease.
  DateTime identityTime(DateTime raw, {DateTime? reachedDeadline}) {
    var at = raw.toUtc();
    if (_identityFloor != null && _identityFloor!.isAfter(at)) {
      at = _identityFloor!;
    }
    if (reachedDeadline != null && reachedDeadline.isAfter(at)) {
      at = reachedDeadline.toUtc();
    }
    return _identityFloor = at;
  }

  ({List<CommunityChatMessage> messages, List<CommunityChatMessage> retired})
  retireProofs(
    List<CommunityChatMessage> messages,
    Iterable<CommunityChatMessage> expired,
  ) {
    final expected = {
      for (final message in expired) message.messageRef: message,
    };
    final retired = <CommunityChatMessage>[];
    final next = messages.map((message) {
      final original = expected[message.messageRef];
      if (original?.senderRef != message.senderRef ||
          original?.authorIdentity?.sameObservationAs(
                message.authorIdentity ??
                    const CommunityAuthorProjection.unavailable(),
              ) !=
              true) {
        return message;
      }
      retired.add(message);
      return CommunityChatMessage.neutralAuthor(message);
    }).toList();
    return (messages: next, retired: retired);
  }

  int epoch = 0;
  List<String> _visible = const [];
  List<int> _logicalVisible = const [];
  bool _recoveryAttempted = false;
  final _verified = <String>{};
  final _pending = <String>[];
  bool get hasPending => _pending.isNotEmpty;
  bool canPresent(String reference) => _verified.contains(reference);
  void retire() {
    suspend();
    _visible = const [];
    _logicalVisible = const [];
    _recoveryAttempted = false;
  }

  /// Leave the measured window in place so redraw cannot self-enqueue IO.
  void suspend() {
    epoch++;
    _verified.clear();
    _pending.clear();
  }

  bool observe(Iterable<CommunityChatMessage> messages) {
    final rows = messages.toList();
    final next = rows.map((message) => message.messageRef).toSet().toList();
    if (next.length > 500) throw StateError('Unbounded author viewport');
    if (_same(_visible, next)) return false;
    final logical = rows.map((message) => message.sequence).toList();
    final sameLogical = _same(_logicalVisible, logical);
    suspend();
    if (!sameLogical) _recoveryAttempted = false;
    _visible = List.unmodifiable(next);
    _logicalVisible = List.unmodifiable(logical);
    refresh();
    return true;
  }

  CommunityChatReferenceRecovery? beginReferenceRecovery(
    int capturedEpoch,
    List<CommunityChatMessage> retained,
  ) {
    if (capturedEpoch != epoch || _recoveryAttempted || _visible.isEmpty) {
      return null;
    }
    final byReference = {for (final row in retained) row.messageRef: row};
    final rows = _visible
        .map((ref) => byReference[ref])
        .whereType<CommunityChatMessage>()
        .toList();
    if (rows.length != _visible.length || rows.length > 500) {
      return null;
    }
    var before = 0;
    for (final row in rows) {
      if (row.sequence >= before) before = row.sequence + 1;
    }
    if (before <= 0) return null;
    _recoveryAttempted = true;
    return (epoch: epoch, before: before, messages: List.unmodifiable(rows));
  }

  bool referenceRecoveryIsCurrent(CommunityChatReferenceRecovery plan) =>
      plan.epoch == epoch &&
      _same(_visible, plan.messages.map((row) => row.messageRef).toList());

  List<CommunityChatMessage> applyAuthorUpdates(
    List<CommunityChatMessage> messages,
    CommunityChatPage page,
    List<String> observed,
    DateTime Function() now,
  ) {
    final updates = {
      for (final update in page.authorUpdates)
        if (observed.contains(update.messageRef)) update.messageRef: update,
    };
    return messages.map((message) {
      final update = updates[message.messageRef];
      final valid =
          update != null &&
          update.senderRef == message.senderRef &&
          update.sequence == message.sequence;
      final identity = valid
          ? update.identity
          : observed.contains(message.messageRef) &&
                !page.messages.any(
                  (row) => row.messageRef == message.messageRef,
                )
          ? const CommunityAuthorProjection.unavailable()
          : message.authorIdentity;
      return identity == null
          ? message
          : CommunityChatMessage.withAuthor(message, identity.admit(now()));
    }).toList();
  }

  ({List<CommunityChatMessage> messages, List<CommunityChatMessage> retired})
  recoverReferences(
    CommunityChatReferenceRecovery plan,
    List<CommunityChatMessage> retained,
    CommunityChatPage root,
    DateTime Function() now,
  ) {
    if (!referenceRecoveryIsCurrent(plan)) {
      return (messages: retained, retired: const []);
    }
    final captured = {for (final row in plan.messages) row.sequence: row};
    final incoming = {for (final row in root.messages) row.sequence: row};
    final replaced = <String, String>{};
    final retired = <CommunityChatMessage>[];
    final messages = retained.map((row) {
      final old = captured[row.sequence], fresh = incoming[row.sequence];
      if (old == null ||
          fresh == null ||
          row.messageRef != old.messageRef ||
          !_sameContent(old, row) ||
          !_sameContent(old, fresh)) {
        return row;
      }
      replaced[old.messageRef] = fresh.messageRef;
      retired.add(old);
      return CommunityChatMessage.withAuthor(
        fresh,
        (fresh.authorIdentity ?? const CommunityAuthorProjection.unavailable())
            .admit(now()),
      );
    }).toList();
    _visible = List.unmodifiable(_visible.map((ref) => replaced[ref] ?? ref));
    _verified.removeAll(replaced.keys);
    _verified.addAll(replaced.values);
    _pending.removeWhere(replaced.containsKey);
    return (messages: messages, retired: retired);
  }

  bool _sameContent(CommunityChatMessage left, CommunityChatMessage right) =>
      left.sequence == right.sequence &&
      left.text == right.text &&
      left.createdAt == right.createdAt &&
      left.isSelf == right.isSelf &&
      left.localRequestId == right.localRequestId &&
      left.hasAttachment == right.hasAttachment;

  bool _same<T>(List<T> left, List<T> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  void refresh() {
    _pending.clear();
    _pending.addAll(_visible);
  }

  List<String> takeBatch() {
    final length = _pending.length > 50 ? 50 : _pending.length;
    final result = _pending.sublist(0, length);
    _pending.removeRange(0, length);
    return result;
  }

  void verified(int capturedEpoch, Iterable<String> references) {
    if (capturedEpoch == epoch) {
      _verified.addAll(references.where(_visible.contains));
    }
  }
}
