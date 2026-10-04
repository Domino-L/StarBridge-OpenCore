import 'dart:async';

import '../../features/communities/community_chat_port.dart';
import 'menu_organization_presentation.dart';

/// Sidebar summaries are optional. Read the selected page first; refresh these
/// independently with at most three cancellable requests and no read receipts.
final class MenuOrganizationPreviews {
  MenuOrganizationPreviews(this.port, this.onPreview);
  final CommunityChatPort port;
  final void Function(String, Map<String, Object?>) onPreview;
  final _cache = <String, Map<String, Object?>>{};
  final _pending = <String>{};
  final _revisions = <String, int>{};
  final _queue = <String>[];
  Set<String> _targets = {};
  int _epoch = 0, _workers = 0;
  bool _disposed = false;

  void rebind(String old, String target) {
    final cached = _cache.remove(old);
    if (cached != null) _cache[target] = Map.of(cached);
    _targets.remove(old);
  }

  Map<String, Object?> value(String target) =>
      _cache[target] ?? const {'summary': '正在读取聊天摘要', 'time': ''};

  /// Reuse a successful, authorized chat read; this never marks messages read.
  void observe(String target, List<CommunityChatMessage> messages, int unread) {
    if (_disposed) return;
    _revisions[target] = (_revisions[target] ?? 0) + 1;
    final value = _summary(messages, unread);
    _cache[target] = value;
    onPreview(target, value);
  }

  Map<String, Object?> _summary(
    List<CommunityChatMessage> messages,
    int unread,
  ) {
    final last = messages.lastOrNull;
    final time = last?.createdAt.toLocal();
    final text = last == null
        ? '暂无消息'
        : '${last.callsign.isEmpty ? last.gameId : last.callsign}：${last.text.isEmpty && last.hasAttachment ? '[附件]' : last.text}';
    return {
      'summary': String.fromCharCodes(
        text.replaceAll(RegExp(r'\s+'), ' ').runes.take(580),
      ),
      'time': time == null
          ? ''
          : '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
      'unread': unread,
    };
  }

  void refresh(Iterable<String> targets, {String? observedTarget}) {
    if (_disposed) return;
    _targets = targets.toSet();
    _cache.removeWhere((key, _) => !_targets.contains(key));
    _revisions.removeWhere((key, _) => !_targets.contains(key));
    for (final target in _targets) {
      if (target == observedTarget) continue;
      if (_pending.add(target)) _queue.add(target);
    }
    _start();
  }

  void _start() {
    while (!_disposed && _workers < 3 && _queue.isNotEmpty) {
      final target = _queue.removeAt(0);
      if (!_targets.contains(target)) {
        _pending.remove(target);
        continue;
      }
      final epoch = _epoch;
      _workers++;
      unawaited(
        _load(target, epoch).whenComplete(() {
          _workers--;
          _start();
        }),
      );
    }
  }

  Future<void> _load(String target, int epoch) async {
    final revision = _revisions[target] ?? 0;
    Map<String, Object?> value;
    try {
      final page = await (port is CommunityChatPreviewPort
          ? (port as CommunityChatPreviewPort).readChatPreview(target)
          : port.readChat(target).timeout(const Duration(seconds: 2)));
      if (page.targetRef != target) throw StateError('wrong scope');
      value = _summary(page.messages, page.unreadCount);
    } on Object catch (error) {
      value = organizationTransientRead(error) && _cache[target] != null
          ? _cache[target]!
          : {'summary': '暂时无法读取聊天摘要', 'time': ''};
    }
    if (_disposed || epoch != _epoch) return;
    _pending.remove(target);
    if (!_targets.contains(target) || revision != (_revisions[target] ?? 0)) {
      return;
    }
    _cache[target] = value;
    onPreview(target, value);
  }

  void clear() {
    _epoch++;
    _targets.clear();
    _queue.clear();
    _pending.clear();
    _cache.clear();
    _revisions.clear();
  }

  void dispose() {
    _disposed = true;
    clear();
  }
}
