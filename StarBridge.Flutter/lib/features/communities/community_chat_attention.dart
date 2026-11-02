import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../shared/diagnostics/loading_read_scope.dart';
import 'communities_module.dart';
import 'community_activity_port.dart';
import 'community_chat_controller.dart';
import 'community_chat_port.dart';

/// Account-scoped unread projection, independent of any mounted chat page.
/// Uses the existing authorized preview and activity transport; no timer, media,
/// message cache, or read receipts are owned here.
final class CommunityChatAttention extends ChangeNotifier {
  CommunityChatAttention(CommunitiesPort port)
    : this._(port, port.invalidations);

  CommunityChatAttention.forChat(
    CommunityChatPort port, {
    bool observeActivity = true,
  }) : this._(port, port.invalidations, observeActivity: observeActivity);

  CommunityChatAttention._(
    this.port,
    Stream<void> invalidations, {
    bool observeActivity = true,
  }) {
    _invalidations = invalidations.listen((_) => clear());
    if (observeActivity && port is CommunityActivityPort) {
      _activity = (port as CommunityActivityPort).workspaceChanges.listen(
        (_) => refresh(),
      );
    }
  }
  final Object port;
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
  // The Host has four ordinary request workers. Periodic reconciliation uses
  // one so page reads keep three; events and explicit refreshes use three.
  static const _eventWorkers = 3, _reconcileWorkers = 1;
  int _workerLimit = _eventWorkers;
  bool _closed = false;

  // Observed read failure only; callers retain their own admission policy.
  final _readErrors = <String, String>{};
  String? readError(String target) => _readErrors[target];
  int count(String target) => _counts[target] ?? 0;

  /// The newest messages, oldest first, from the same authorized reads as the
  /// unread count, for the rail's chat tile; nothing is fetched for them. Each
  /// read replaces the list, so a removed message does not linger.
  List<CommunityChatMessage> recent(String target) =>
      _recent[target] ?? const [];
  static const recentLimit = 8;
  final _recent = <String, List<CommunityChatMessage>>{};
  void _keepRecent(String target, List<CommunityChatMessage> messages) {
    final previous = _recent[target];
    if (messages.isEmpty) {
      if (_recent.remove(target) != null && !_closed) notifyListeners();
      return;
    }
    if (previous != null && previous.last.sequence > messages.last.sequence) {
      return;
    }
    final next = messages.length <= recentLimit
        ? messages
        : messages.sublist(messages.length - recentLimit);
    if (previous != null &&
        previous.length == next.length &&
        Iterable.generate(next.length).every(
          (i) =>
              previous[i].messageRef == next[i].messageRef &&
              previous[i].text == next[i].text,
        )) {
      return;
    }
    _recent[target] = List.unmodifiable(next);
    if (!_closed) notifyListeners();
  }

  int get totalCount => _counts.values.fold(0, (total, count) => total + count);
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
    _recent.removeWhere((key, _) => !next.contains(key));
    _readThrough.removeWhere((key, _) => !next.contains(key));
    _revision.removeWhere((key, _) => !next.contains(key));
    _observed.removeWhere((key, _) => !next.contains(key));
    _retry.removeWhere((key) => !next.contains(key));
    _readErrors.removeWhere((key, _) => !next.contains(key));
    _targets = next;
    if (removedUnread) notifyListeners();
    refresh();
  }

  /// [reconcile] is the periodic fallback for missed activity events. It never
  /// stacks: while an earlier pass is still reading it is skipped, so slow
  /// Host reads cannot keep every worker permanently busy. Activity events and
  /// explicit refreshes keep the original re-read-after-current behaviour.
  void refresh({bool retryOnly = false, bool reconcile = false}) {
    if (_closed ||
        port is! CommunityChatPort ||
        !(port as CommunityChatPort).chatAvailable) {
      return;
    }
    if (reconcile && (_workers > 0 || _queue.isNotEmpty)) return;
    _workerLimit = reconcile ? _reconcileWorkers : _eventWorkers;
    for (final target in _targets) {
      if (retryOnly && !_retry.contains(target)) continue;
      if (_pending.add(target)) {
        _queue.add(target);
      } else if (!reconcile) {
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
      _keepRecent(target, chat.messages.toList());
      _setCount(target, chat.unreadCount);
    }
  }

  void _setCount(String target, int value) {
    if (count(target) == value) return;
    _counts[target] = value;
    notifyListeners();
  }

  void _start() {
    while (!_closed && _workers < _workerLimit && _queue.isNotEmpty) {
      final target = _queue.removeAt(0), epoch = _epoch;
      _workers++;
      unawaited(
        backgroundLoadingRead(() => _read(target, epoch)).whenComplete(() {
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
      final recovered = _readErrors.remove(target) != null;
      _retry.remove(target);
      _latest[target] = page.latestSequence;
      _keepRecent(target, page.messages);
      _setCount(
        target,
        page.latestSequence <= (_readThrough[target] ?? 0)
            ? 0
            : page.unreadCount,
      );
      if (recovered && current()) notifyListeners();
    } catch (error) {
      if (!current()) return;
      final code = error is CommunityFailure ? error.code : 'unavailable';
      final changed = _readErrors[target] != code;
      _readErrors[target] = code;
      if (changed) notifyListeners();
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
      _keepRecent(target, const []);
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
    _recent.clear();
    _readThrough.clear();
    _revision.clear();
    _observed.clear();
    _readErrors.clear();
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
