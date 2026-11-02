import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/account/account_models.dart';
import '../../features/direct_messages/direct_messages_contract.dart';
import '../../features/direct_messages/direct_message_directory_comparison.dart';
import '../../features/direct_messages/direct_message_receive_polling.dart';
import '../../shared/diagnostics/loading_metrics.dart';
import '../../shared/diagnostics/loading_read_scope.dart';

/// App-lifetime directory reception. UI history, sends and receipts retain
/// independent cancellable ports. Offered DTOs never grant read authority.
final class DirectMessageRefresh {
  DirectMessageRefresh(this.port, this.account) {
    _polling = DirectMessageReceivePolling(
      read: _poll,
      isHealthy: () => directMessageReceptionHealthy(port),
      foreground: () => _views.any((view) => view.visible),
    );
    _background = _polling.observe(() => _admitted);
    _accountKey = _key;
    account.addListener(_changed);
    _events = port.invalidations.listen((_) => _retire(hard: true));
    if (port is DirectMessageActivityPort) {
      _activity = (port as DirectMessageActivityPort).changes.listen(
        (_) { _genericPending = true; _background.wake(); },
      );
    }
    if (port is DirectMessageHintPort) {
      _hints = (port as DirectMessageHintPort).hints.listen((targets) {
        if (!_admitted) return;
        _hintPending = true;
        _hintTargets.addAll(targets);
        _background.wake();
      });
    }
    if (port is DirectMessageReadScopePort) {
      _detachScope = (port as DirectMessageReadScopePort).observeReadScope(
        (hard) => _retire(hard: hard),
      );
    }
    scheduleMicrotask(() {
      if (!_closed && _cycle == null) _background.wake();
    });
  }
  final DirectMessagesPort port;
  final ValueNotifier<int> unread = ValueNotifier(0);
  final ValueListenable<AccountProjection> account;
  final _views = <_ReceptionView>{};
  late final DirectMessageReceivePolling _polling;
  late final DirectMessageReceiveLease _background;
  late final StreamSubscription<void> _events;
  StreamSubscription<void>? _activity;
  StreamSubscription<List<String>>? _hints;
  final _hintTargets = <String>{};
  bool _hintPending = false, _genericPending = false;
  void Function()? _detachScope;
  Object? _accountKey;
  List<Conversation>? _lastRows;
  _DirectoryCycle? _cycle;
  Future<void>? _rawTail;
  bool _closed = false;
  int _epoch = 0;
  bool get _signedIn =>
      account.value.isSignedIn || account.value.isLegacyAccount;
  DirectMessageReadScope? get _scope => port is DirectMessageReadScopePort
      ? (port as DirectMessageReadScopePort).readScope
      : null;
  bool get _admitted =>
      !_closed &&
      _signedIn &&
      (port is! DirectMessageReadScopePort ||
          (_scope != null && _scope!.generation == account.value.generation));
  Object get _key =>
      (account.value.generation, account.value.sessionState, _scope);

  DirectMessagesPort borrow(DirectMessagesPort consumer) {
    if (identical(port, consumer)) {
      throw ArgumentError(
        'Reception directory port must not be lent to a view',
      );
    }
    if (port is! DirectMessageReadScopePort ||
        consumer is! DirectMessageReadScopePort) {
      return consumer;
    }
    final view = _ReceptionView(this, consumer);
    if (!_closed) _views.add(view);
    return view;
  }

  void _changed() {
    if (_closed || _key == _accountKey) return;
    _retire(hard: true);
  }

  void _retire({required bool hard, bool wake = true}) {
    if (_closed) return;
    _epoch++;
    _hintTargets.clear();
    _hintPending = _genericPending = false;
    _accountKey = _key;
    final old = _cycle;
    _cycle = null;
    if (old != null) {
      old.result = DirectMessageReceiveResult.invalidated;
      old.retiredFailure = DirectReadFailure(
        hard ? 'identity_unavailable' : 'unavailable',
      );
    }
    port.cancel();
    if (hard) {
      _lastRows = null;
      unread.value = 0;
    }
    for (final view in _views.toList()) {
      view.retire(hard);
    }
    _polling.invalidate();
    if (wake) _background.wake();
  }

  bool _accepts(_ReceptionView view) =>
      _admitted &&
      !view.closed &&
      (view.raw as DirectMessageReadScopePort).readScope == _scope;

  Future<List<Conversation>> _directory(
    _ReceptionView view, {
    required bool published,
  }) {
    final future = _directoryCore(view, published: published);
    final metrics = LoadingMetrics.current;
    if (metrics == null || metrics.stopped) return future;
    final release = metrics.observe('directMessages.read', future,
        transport: false);
    view._readMeters.add(release);
    unawaited(future.then<void>((_) {
      view._readMeters.remove(release);
    },
        onError: (Object _, StackTrace _) {
      view._readMeters.remove(release);
    }));
    return future;
  }

  Future<List<Conversation>> _directoryCore(
    _ReceptionView view, {
    required bool published,
  }) async {
    if (!_accepts(view)) throw const DirectReadFailure('unavailable');
    if (_accountKey != _key) _retire(hard: false);
    if (published && view.offeredEpoch == _epoch) {
      final offer = view.offer, failure = view.failure;
      view.clearOffer();
      if (failure != null) throw failure;
      if (offer != null) return offer;
    }
    view.clearOffer();
    final revision = view.revision;
    final active = _cycle;
    final cycle = _cycle ??= _newCycle();
    cycle.requesters.add(view);
    if (active == null) _background.wake();
    _start(cycle);
    final rows = await cycle.rows.future;
    if (!_accepts(view) || revision != view.revision || cycle.epoch != _epoch) {
      throw cycle.retiredFailure ??
          const DirectReadFailure('identity_unavailable');
    }
    return rows;
  }

  Future<DirectMessageReceiveResult> _poll() => backgroundLoadingRead(_pollCore);

  Future<DirectMessageReceiveResult> _pollCore() async {
    if (!_admitted) return DirectMessageReceiveResult.skipped;
    if (_accountKey != _key) _retire(hard: false);
    final cycle = _cycle ??= _newCycle();
    _start(cycle);
    try {
      await cycle.rows.future;
    } catch (_) {
      /* classified by owner */
    }
    return cycle.result;
  }

  void _start(_DirectoryCycle cycle) {
    if (cycle.started) return;
    cycle.started = true;
    final previous = _rawTail;
    final done = Completer<void>();
    _rawTail = done.future;
    unawaited(() async {
      try {
        if (previous != null) await previous;
        // The shared reception owner owns physical work even when a view
        // starts a fresh cycle while the polling callback is still busy.
        // _directory independently observes each view's logical Future.
        await backgroundLoadingRead(() => _read(cycle));
      } finally {
        done.complete();
        if (identical(_rawTail, done.future)) _rawTail = null;
      }
    }());
  }

  _DirectoryCycle _newCycle() {
    final targets = _hintPending && !_genericPending ? Set<String>.of(_hintTargets) : null;
    _hintTargets.clear();
    _hintPending = _genericPending = false;
    return _DirectoryCycle(_epoch, _scope, targets);
  }

  Future<void> _read(_DirectoryCycle cycle) async {
    if (_closed ||
        cycle.epoch != _epoch ||
        cycle.scope != _scope ||
        !_admitted) {
      if (!cycle.rows.isCompleted) {
        cycle.rows.completeError(
          cycle.retiredFailure ??
              const DirectReadFailure('identity_unavailable'),
        );
      }
      return;
    }
    List<Conversation>? rows;
    DirectReadFailure? failure;
    try {
      rows = List<Conversation>.unmodifiable(await port.directory());
    } catch (error) {
      failure = error is DirectReadFailure
          ? error
          : const DirectReadFailure('unavailable');
    }
    if (_closed ||
        cycle.epoch != _epoch ||
        cycle.scope != _scope ||
        !_admitted) {
      if (!cycle.rows.isCompleted) {
        cycle.rows.completeError(
          cycle.retiredFailure ??
              const DirectReadFailure('identity_unavailable'),
        );
      }
      return;
    }
    if (identical(_cycle, cycle)) _cycle = null;
    if (failure == null) {
      cycle.result =
          _lastRows != null && sameDirectMessageDirectory(_lastRows!, rows!)
          ? DirectMessageReceiveResult.unchanged
          : DirectMessageReceiveResult.changed;
      _lastRows = rows;
      unread.value = rows!.fold(
        0,
        (sum, row) => sum + (row.unread < 0 ? 0 : row.unread),
      );
    } else {
      cycle.result = DirectMessageReceiveResult.failed;
      if (const {
        'forbidden',
        'identity_unavailable',
        'target_changed',
      }.contains(failure.code)) {
        unread.value = 0;
        _lastRows = null;
      }
    }
    for (final view in _views.toList()) {
      if (cycle.requesters.contains(view) || !_accepts(view)) continue;
      view.offer = rows;
      view.failure = failure;
      view.offeredEpoch = _epoch;
      final withdraw =
          failure != null &&
          const {
            'forbidden',
            'identity_unavailable',
            'target_changed',
          }.contains(failure.code);
      if (withdraw || (view.visible && (cycle.targets == null ||
          (view.historyTarget != null && cycle.targets!.contains(view.historyTarget))))) {
        view.activity.add(null);
      } else if (view.visible &&
          cycle.result == DirectMessageReceiveResult.changed) {
        view.directoryActivity.add(null);
      }
    }
    if (!cycle.rows.isCompleted) {
      if (failure != null) {
        cycle.rows.completeError(failure);
      } else {
        cycle.rows.complete(rows!);
      }
    }
  }

  void dispose() {
    if (_closed) return;
    _retire(hard: true, wake: false);
    _closed = true;
    _background.dispose();
    _polling.dispose();
    _detachScope?.call();
    account.removeListener(_changed);
    unawaited(_events.cancel());
    unawaited(_activity?.cancel());
    unawaited(_hints?.cancel());
    _views.clear();
    port.cancel();
    unawaited(port.close());
    unread.dispose();
  }
}

final class _DirectoryCycle {
  _DirectoryCycle(this.epoch, this.scope, this.targets);
  final int epoch;
  final DirectMessageReadScope? scope;
  final Set<String>? targets;
  final rows = Completer<List<Conversation>>();
  final requesters = <_ReceptionView>{};
  bool started = false;
  DirectReadFailure? retiredFailure;
  DirectMessageReceiveResult result = DirectMessageReceiveResult.invalidated;
}

final class _ReceptionView
    implements
        DirectMessagesPort,
        DirectMessageDirectoryUpdatesPort,
        DirectMessageReceptionPort,
        DirectMessageActivityPort,
        DirectMessageDirectoryActivityPort,
        DirectMessageActivityHealthPort,
        DirectMessageSender,
        DirectReadReceiptPort,
        DirectViewerAvatarPort {
  _ReceptionView(this.owner, this.raw);
  final DirectMessageRefresh owner;
  final DirectMessagesPort raw;
  final activity = StreamController<void>.broadcast();
  final directoryActivity = StreamController<void>.broadcast();
  final events = StreamController<void>.broadcast();
  final _leases = <DirectMessageReceiveLease>{};
  final _readMeters = <LoadingReadRelease>{};
  void _retireReadMeters(LoadingReadRetirement reason) {
    for (final release in _readMeters.toList()) {
      release(reason);
    }
    _readMeters.clear();
  }
  bool closed = false;
  int revision = 0, offeredEpoch = -1;
  List<Conversation>? offer;
  DirectReadFailure? failure;
  String? historyTarget;
  bool get visible => !closed && _leases.any((lease) => lease.isVisible());
  void clearOffer() {
    offer = null;
    failure = null;
    offeredEpoch = -1;
  }

  void retire(bool hard) {
    _retireReadMeters(LoadingReadRetirement.invalidated);
    clearOffer();
    if (hard) historyTarget = null;
    if (hard && !closed) {
      revision++;
      events.add(null);
    }
  }

  @override
  Stream<void> get invalidations => events.stream;
  @override
  Stream<void> get changes => activity.stream;
  @override
  Stream<void> get directoryChanges => directoryActivity.stream;
  // Root reception owns fallback as well as push; a child watchdog leases it.
  @override
  bool get activityHealthy => owner._accepts(this);
  @override
  DirectMessageReceiveLease observeVisibleReception(bool Function() visible) {
    late final DirectMessageReceiveLease lease;
    lease = owner._polling.observe(
      () => owner._accepts(this) && visible(),
      onDispose: () => _leases.remove(lease),
    );
    if (closed || owner._closed) {
      lease.dispose();
    } else {
      _leases.add(lease);
    }
    return lease;
  }

  @override
  Future<List<Conversation>> directory() =>
      owner._directory(this, published: false);
  @override
  Future<List<Conversation>> receiveDirectory() =>
      owner._directory(this, published: true);
  @override
  Future<DirectPage> history(String ref, {int before = 0, int after = 0}) {
    historyTarget = ref;
    return closed || owner._closed
      ? Future.error(const DirectReadFailure('unavailable'))
      : raw.history(ref, before: before, after: after);
  }
  @override
  bool get supportsSending =>
      !closed &&
      !owner._closed &&
      raw is DirectMessageSender &&
      (raw as DirectMessageSender).supportsSending;
  @override
  Future<DirectSendResult> send(String ref, String text, String id) =>
      supportsSending
      ? (raw as DirectMessageSender).send(ref, text, id)
      : Future.value(const DirectSendResult('rejected', error: 'unavailable'));
  @override
  bool get supportsReadReceipts =>
      !closed &&
      !owner._closed &&
      raw is DirectReadReceiptPort &&
      (raw as DirectReadReceiptPort).supportsReadReceipts;
  @override
  Future<DirectReadReceipt> markRead(String ref, int through) =>
      supportsReadReceipts
      ? (raw as DirectReadReceiptPort).markRead(ref, through)
      : Future.error(const DirectReadFailure('unavailable'));
  @override
  String? get viewerAvatar => !closed && raw is DirectViewerAvatarPort
      ? (raw as DirectViewerAvatarPort).viewerAvatar
      : null;
  @override
  void cancel() {
    _retireReadMeters(closed ? LoadingReadRetirement.disposed
        : LoadingReadRetirement.cancelled);
    revision++;
    clearOffer();
    raw.cancel();
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    owner._views.remove(this);
    for (final lease in _leases.toList()) {
      lease.dispose();
    }
    cancel();
    await raw.close();
    await events.close();
    await activity.close();
    await directoryActivity.close();
  }
}
