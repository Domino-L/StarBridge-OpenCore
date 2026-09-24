import 'direct_messages_module.dart';
import '../communities/community_invitation_attachment.dart';

final class ExampleDirectMessages
    implements DirectMessagesPort, DirectMessageSender, DirectReadReceiptPort {
  final Map<String, List<DirectMessage>> _sent = {};
  final Map<String, int> _readThrough = {};
  @override
  bool get supportsReadReceipts => true;
  int _unread(String ref) => ref == _friend
      ? [57, 59].where((n) => n > (_readThrough[ref] ?? 0)).length
      : (_readThrough[ref] ?? 0) < 1
      ? 1
      : 0;
  @override
  Future<DirectReadReceipt> markRead(String ref, int through) async {
    if (ref != _friend && ref != _request) {
      throw const DirectReadFailure('target_changed');
    }
    final received = ref == _friend ? 59 : 1;
    if (through <= 0 || through > received) {
      throw const DirectReadFailure('data_invalid');
    }
    final previous = _readThrough[ref] ?? 0;
    _readThrough[ref] = through > previous ? through : previous;
    return DirectReadReceipt(_readThrough[ref]!, _unread(ref));
  }

  @override
  bool get supportsSending => true;
  @override
  Future<DirectSendResult> send(
    String ref,
    String text,
    String clientMessageId,
  ) async {
    if (ref != _friend && ref != _request) {
      return const DirectSendResult('rejected', error: 'target_changed');
    }
    final sent = _sent.putIfAbsent(ref, () => []);
    final message = DirectMessage(
      (ref == _friend ? 61 : 2) + sent.length,
      clientMessageId,
      false,
      text.trim(),
      _time.add(Duration(minutes: (ref == _friend ? 61 : 2) + sent.length)),
      null,
    );
    sent.add(message);
    return DirectSendResult('sent', message: message);
  }

  static final _time = DateTime.utc(2026, 9, 6, 12);
  static const _friend = '00000000000000000000000000000001';
  static const _request = '00000000000000000000000000000002';
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<List<Conversation>> directory() async => [
    Conversation(
      _friend,
      '示例好友 (Example)',
      '这是会话历史示例',
      _time,
      _unread(_friend),
      'friend',
      conversationKey: '1'.padLeft(64, '0'),
    ),
    Conversation(
      _request,
      '示例用户 (Example_Request)',
      '这是一条消息请求',
      _time,
      _unread(_request),
      'request_incoming',
    ),
  ];
  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async {
    if (ref != _friend && ref != _request) {
      throw const DirectReadFailure('target_changed');
    }
    final all = [
      for (var n = 1; n <= (ref == _friend ? 60 : 1); n++)
        DirectMessage(
          n,
          'example-$n',
          n.isOdd,
          ref == _friend ? '这是会话历史示例 $n' : '这是一条消息请求',
          _time.add(Duration(minutes: n)),
          ref == _friend && n == 59 ? 'fleet_invitation' : null,
          communityInvitation: ref == _friend && n == 59
              ? const CommunityInvitationAttachment(
                  title: '组织邀请 · 新手互助',
                  summary: '查看示例组织详情后决定是否加入。',
                  inviteCode: 'EXAMPLE-ORG',
                )
              : null,
        ),
      ...?_sent[ref],
    ];
    final filtered = all
        .where((m) => before > 0 ? m.sequence < before : m.sequence > after)
        .toList();
    final page = after > 0
        ? filtered.take(50).toList()
        : filtered
              .skip(filtered.length > 50 ? filtered.length - 50 : 0)
              .toList();
    final oldest = page.firstOrNull?.sequence ?? 0;
    return DirectPage(
      ref,
      page,
      oldest,
      all.last.sequence,
      oldest > 1,
      ref == _friend
          ? 'friend'
          : (_sent[_request]?.isNotEmpty ?? false)
          ? 'accepted'
          : 'request_incoming',
      canSend: true,
    );
  }

  @override
  void cancel() {}
  @override
  Future<void> close() async {}
}
