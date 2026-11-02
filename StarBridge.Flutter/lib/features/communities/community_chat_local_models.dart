import 'communities_module.dart' show CommunityFailure;
import 'community_chat_port.dart';
import 'community_chat_send_port.dart';

/// What one read really was, which may differ from what was asked for, and how
/// it went. A read that did not run has no result.
typedef ChatReadResult = ({bool renewal, bool ok});

/// A full read still owed: a push met a busy read, a full read failed, or a
/// renewal saw past the high-water mark. The schedule runs it and counts it.
final class CommunityChatCatchUp {
  bool due = false;
  int _seen = 0;
  void Function()? onDue, onFullRead;

  /// Each newer mark asks once, so a renewal and a full read that disagree about
  /// the latest message cannot turn every renewal into a full read.
  void renewalSaw(int sequence, int latest) {
    if (sequence <= latest || sequence <= _seen) return;
    _seen = sequence;
    due = true;
  }
}

/// Local presentation only: never participates in server cursors or receipts.
final class CommunityLocalMessage {
  CommunityLocalMessage(this.intent, this.createdAt);
  CommunityChatSendIntent intent;
  final DateTime createdAt;
  String state = 'sending';
  String? error;
  int? sequence;

  void settle(String state, String? error, int? sequence) {
    this.state = state;
    this.error = error;
    this.sequence = sequence;
  }
}

/// Account-scoped presentation state, never a server cursor or read receipt.
final class CommunityChatViewport {
  const CommunityChatViewport({
    required this.pixels,
    required this.followLatest,
    required this.observedLatest,
    this.anchorSequence,
    this.anchorOffset = 0,
  });
  final double pixels, anchorOffset;
  final bool followLatest;
  final int observedLatest;
  final int? anchorSequence;
}

/// One read's messages merged into what is held, in order and without repeats;
/// a page outside what was asked for, or with duplicates, is invalid.
List<CommunityChatMessage> mergeCommunityChatPage(
  List<CommunityChatMessage> held,
  CommunityChatPage page, {
  required String target,
  required int after,
  required int before,
  required bool renewed,
}) {
  if (page.targetRef != target ||
      page.messages.any(
        (m) =>
            after > 0 && m.sequence <= after ||
            before > 0 && m.sequence >= before,
      )) {
    throw const CommunityFailure('dataInvalid');
  }
  final refreshed = page.messages.map((m) => m.sequence).toSet();
  final merged = [
    ...held.where((m) => !renewed || !refreshed.contains(m.sequence)),
    ...page.messages,
  ]..sort((a, b) => a.sequence.compareTo(b.sequence));
  if (merged.map((m) => m.sequence).toSet().length != merged.length ||
      merged.map((m) => m.messageRef).toSet().length != merged.length) {
    throw const CommunityFailure('dataInvalid');
  }
  return merged;
}
