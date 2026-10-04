import 'dart:async';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_activity_port.dart';
import 'community_chat_controller.dart';
import 'community_chat_port.dart';

/// Account-scoped unread projection, independent of any mounted chat page.
/// Uses the existing authorized preview and activity transport; no timer, media,
/// message cache, or read receipts are owned here.
final class CommunityChatAttention extends ChangeNotifier {
  CommunityChatAttention(this.port) {
    _invalidations = port.invalidations.listen((_) => clear());
    if (port is CommunityActivityPort) {
      _activity = (port as CommunityActivityPort).workspaceChanges.listen(
        (_) => refresh(),
      );
    }
  }
  final CommunitiesPort port;
  late final StreamSubscription<void> _invalidations;
  StreamSubscription<void>? _activity;
  Set<String> _targets = {};
  final _counts = <String, int>{},
      _latest = <String, int>{},
      _readThrough = <String, int>{};
  final _revision = <String, int>{};
  final _observed = <String, (int, int, int)>{};
  final _pending = <String>{}, _again = <String>{};
  final _retry = <String>{};
  final _queue = <String>[];
  int _epoch = 0, _workers = 0;
  bool _closed = false;

  int count(String target) => _counts[target] ?? 0;
  bool get needsReconciliation => _retry.isNotEmpty;

  void bind(Iterable<String> targets) {
    if (_closed) return;
    final next = targets.toSet();
    if (setEquals(next, _targets)) return;
    // Retire in-flight reads, but do not flash unaffected organizations to zero.
    _epoch++;
    _queue.clear();
    _pending.clear();
    _again.clear();
    final removedUnread = _counts.entries.any(
      (e) => !next.contains(e.key) && e.value > 0,
    );
    _counts.removeWhere((key, _) => !next.contains(key));
    _latest.removeWhere((key, _) => !next.contains(key));
    _readThrough.removeWhere((key, _) => !next.contains(key));
    _revision.removeWhere((key, _) => !next.contains(key));
    _observed.removeWhere((key, _) => !next.contains(key));
    _retry.removeWhere((key) => !next.contains(key));
    _targets = next;
    if (removedUnread) notifyListeners();
    refresh();
  }

  void refresh({bool retryOnly = false}) {
    if (_closed ||
        port is! CommunityChatPort ||
        !(port as CommunityChatPort).chatAvailable) {
      return;
    }
    for (final target in _targets) {
      if (retryOnly && !_retry.contains(target)) continue;
      if (_pending.add(target)) {
        _queue.add(target);
      } else {
        _again.add(target);
      }
    }
    _start();
  }

  void observe(CommunityChatController chat) {
    final target = chat.targetRef;
    if (_closed || !_targets.contains(target)) return;
    if (chat.invalidated) {
      _revision[target] = (_revision[target] ?? 0) + 1;
      _setCount(target, 0);
    } else if (chat.hasLoaded) {
      // Receipt presentation can change while a history read is pending or
      // failed. Never retain an optimistic cursor merely because of that read.
      // Snapshot deduplication still ignores loading/draft-only notifications.
      final snapshot = (
        chat.latestSequence,
        chat.displayedReadThrough,
        chat.unreadCount,
      );
      if (_observed[target] == snapshot) return;
      _observed[target] = snapshot;
      if (chat.latestSequence < (_latest[target] ?? 0)) return;
      _revision[target] = (_revision[target] ?? 0) + 1;
      _latest[target] = chat.latestSequence;
      _readThrough[target] = chat.displayedReadThrough;
      _setCount(target, chat.unreadCount);
    }
  }

  void _setCount(String target, int value) {
    if (count(target) == value) return;
    _counts[target] = value;
    notifyListeners();
  }

  void _start() {
    while (!_closed && _workers < 3 && _queue.isNotEmpty) {
      final target = _queue.removeAt(0), epoch = _epoch;
      _workers++;
      unawaited(
        _read(target, epoch).whenComplete(() {
          _workers--;
          if (epoch == _epoch) {
            _pending.remove(target);
            if (_again.remove(target) && _targets.contains(target)) {
              _pending.add(target);
              _queue.add(target);
            }
          }
          _start();
        }),
      );
    }
  }

  Future<void> _read(String target, int epoch) async {
    final revision = _revision[target] ?? 0;
    bool current() => !_closed && epoch == _epoch && _targets.contains(target);
    try {
      final source = port as CommunityChatPort;
      // The bridge owns the request deadline. Do not release a worker on a
      // Dart-only timeout while its underlying request is still running.
      // An unread count is not an optional two-second directory preview.
      // Keep the normal bounded bridge deadline for authorized readback.
      final page = await source.readChat(target);
      if (!current()) return;
      if (page.targetRef != target) throw const CommunityFailure('dataInvalid');
      if (revision != (_revision[target] ?? 0) ||
          page.latestSequence < (_latest[target] ?? 0)) {
        return;
      }
      _retry.remove(target);
      _latest[target] = page.latestSequence;
      _setCount(
        target,
        page.latestSequence <= (_readThrough[target] ?? 0)
            ? 0
            : page.unreadCount,
      );
    } catch (error) {
      if (!current()) return;
      if (error is! CommunityFailure ||
          !const {
            'identityUnavailable',
            'notAllowed',
            'notFound',
            'refreshRequired',
          }.contains(error.code)) {
        _retry.add(target);
        return;
      }
      _retry.remove(target);
      _revision[target] = (_revision[target] ?? 0) + 1;
      _setCount(target, 0);
    }
  }

  void clear() {
    _epoch++;
    _targets.clear();
    _queue.clear();
    _pending.clear();
    _again.clear();
    _retry.clear();
    _counts.clear();
    _latest.clear();
    _readThrough.clear();
    _revision.clear();
    _observed.clear();
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    clear();
    unawaited(_invalidations.cancel());
    unawaited(_activity?.cancel());
    super.dispose();
  }
}
