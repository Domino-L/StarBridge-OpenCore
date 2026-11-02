import 'dart:async';
import 'dart:convert';

import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../shared/diagnostics/loading_read_scope.dart';

/// A data-free, authorized change hint. It does not carry a durable cursor.
final class CommunityActivityHintStrategy {
  CommunityActivityHintStrategy({
    required this.sourceRef,
    required this.command,
    required this.capability,
    required Map<String, Object?> payload,
  }) : payload = Map.unmodifiable(payload);
  final String sourceRef, command, capability;
  final Map<String, Object?> payload;
}

/// One cancellable server wait while organization surfaces have subscribers.
/// Heartbeat replies do not reload content. Reconnects reconcile once.
final class CommunityActivity {
  CommunityActivity(
    this.session, {
    this.onlineAllowed,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    changes = StreamController<void>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
    _events = session.events.listen((event) {
      if (!_closed && event.name == 'account.presentationChanged') {
        // Use the existing read-refresh lane, not account invalidation which
        // would cancel unrelated organization operations and discard drafts.
        changes.add(null);
      }
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _stop();
        _onlinePaused = false;
        if (changes.hasListener) _start();
      }
    });
    _capabilities = session.capabilitiesChanged.listen(
      (_) => reconcileAdmission(),
    );
  }
  final BridgeClientSession session;
  final bool Function()? onlineAllowed;
  final DateTime Function() _now;
  String? _officialSource;
  CommunityActivityHintStrategy? _hintStrategy;
  bool _hintMode = false;
  bool get _scoped => _officialSource != null || _hintStrategy != null;
  void configureHintStrategy(CommunityActivityHintStrategy? strategy) {
    _hintMode = true;
    final previous = _hintStrategy;
    if (previous?.sourceRef == strategy?.sourceRef &&
        previous?.command == strategy?.command &&
        jsonEncode(previous?.payload) == jsonEncode(strategy?.payload)) {
      return;
    }
    if (_officialSource != null) {
      throw StateError('Activity scope already bound');
    }
    _hintStrategy = strategy;
    reconcileAdmission();
    _lastHint = _now();
  }

  bool _officialAvailable = false;
  DateTime? _lastHint;
  final errors = StreamController<String>.broadcast();
  String get _waitName =>
      _hintStrategy?.command ??
      (_officialSource == null ? 'communities.wait' : 'officialFleet.wait');

  /// Reuses this one worker for one immutable official scope. A capability is
  /// transport support only; context and every server wait still authorize it.
  void configureOfficialFleet(String source, {required bool available}) {
    if (!RegExp(r'^officialFleet:[1-9][0-9]{0,18}$').hasMatch(source) ||
        _officialSource != null && _officialSource != source) {
      throw const FormatException('Invalid official activity scope');
    }
    if (_officialSource == source && _officialAvailable == available) return;
    _officialSource = source;
    _officialAvailable = available;
    reconcileAdmission();
  }

  void _hint() {
    _lastHint = _now();
    changes.add(null);
  }

  void reconcileAdmission() {
    _stop();
    _onlinePaused = false;
    if (changes.hasListener) _start();
  }

  late final StreamController<void> changes;
  late final StreamSubscription<Object?> _events;
  late final StreamSubscription<void> _capabilities;
  BridgeRequestOperation? _pending;
  Timer? _timer;
  DateTime? _lastReply;
  bool _presenceEvents = false;
  int _epoch = 0, _version = -1, _failures = 0;
  String _instance = '';
  bool _closed = false;
  bool _onlinePaused = false;
  bool get healthy =>
      _presenceEvents &&
      _lastReply != null &&
      _now().difference(_lastReply!) <
          (_officialSource == null ? _replyFresh : _officialReplyFresh);
  static const _replyFresh = Duration(seconds: 12);

  /// Above the relay's 25 s hold and the Host's budget around it.
  static const _officialReplyFresh = Duration(seconds: 60);

  void _start() => _schedule(Duration.zero, _epoch);
  void _schedule(Duration delay, int epoch) {
    if (_hintMode && _hintStrategy == null) return;
    if (!_closed &&
        !_onlinePaused &&
        onlineAllowed?.call() != false &&
        epoch == _epoch &&
        changes.hasListener) {
      _timer?.cancel();
      final supported =
          session.hostCapabilities.contains(
            _hintStrategy?.capability ?? _waitName,
          ) &&
          (_hintStrategy != null ||
              _officialSource == null ||
              _officialAvailable);
      if (supported) {
        _timer = Timer(delay, () => backgroundLoadingRead(() => _wait(epoch)));
      } else if (_scoped) {
        // Explicit old Host/Relay fallback, still owned by this same worker.
        _timer = Timer(const Duration(seconds: 15), () {
          if (_closed ||
              epoch != _epoch ||
              !changes.hasListener ||
              onlineAllowed?.call() == false) {
            return;
          }
          _hint();
          _schedule(Duration.zero, epoch);
        });
      }
    }
  }

  void _stop() {
    _epoch++;
    _timer?.cancel();
    unawaited(_pending?.cancel());
    _pending = null;
    _lastReply = null;
    _presenceEvents = false;
    _instance = '';
    _version = -1;
    _failures = 0;
    _lastHint = null;
  }

  Future<void> _wait(int epoch) async {
    var delay = const Duration(milliseconds: 150);
    bool current() =>
        !_closed &&
        epoch == _epoch &&
        changes.hasListener &&
        onlineAllowed?.call() != false;
    try {
      _pending = session.beginRequest(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      final account = await _pending!.future;
      if (!current()) return;
      if (!hasRelayAccount(account) || account.accountContext == null) {
        _lastReply = null;
        if (_scoped) errors.add('identityUnavailable');
        delay = const Duration(seconds: 15);
        return;
      }
      _pending = session.beginRequest(
        _waitName,
        timeout: _hintStrategy != null
            ? const Duration(seconds: 12)
            : _officialSource != null
            ? _officialReplyFresh
            : null,
        accountContext: account.accountContext,
        payload:
            _hintStrategy?.payload ??
            {
              'schemaVersion': 1,
              'instance': _instance,
              'version': _version,
              if (_officialSource != null) 'sourceRef': _officialSource,
            },
      );
      final reply = await _pending!.future;
      if (!current()) return;
      final hint = _hintStrategy;
      if (hint != null) {
        final body = reply.payload;
        if (body.length != 3 ||
            body['schemaVersion'] != 2 ||
            body['sourceRef'] != hint.sourceRef ||
            body['changed'] is! bool) {
          throw const FormatException('Invalid scoped activity hint');
        }
        final reconcile =
            _lastHint == null ||
            _now().difference(_lastHint!) >= const Duration(seconds: 15);
        final changed = body['changed'] == true || _failures > 0;
        _failures = 0;
        _lastReply = _now();
        _presenceEvents = true;
        // A false heartbeat is silent except the existing bounded readback.
        // This reconciliation closes the read-to-wait gap without claiming a
        // durable cursor or resuming any write.
        if (changed || reconcile) _hint();
        return;
      }
      final instance = reply.payload['instance'],
          version = reply.payload['version'];
      if (reply.payload['schemaVersion'] != 1 ||
          instance is! String ||
          !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(instance) ||
          version is! int ||
          version < 0 ||
          _officialSource != null &&
              reply.payload['sourceRef'] != _officialSource ||
          instance == _instance && version < _version) {
        throw const FormatException('Invalid organization cursor');
      }
      final changed =
          instance != _instance || version != _version || _failures > 0;
      _instance = instance;
      _version = version;
      _failures = 0;
      _lastReply = _now();
      _presenceEvents =
          reply.payload[_officialSource == null
              ? 'presenceEvents'
              : 'chatEvents'] ==
          true;
      // Every hint costs full reads upstream, and the open chat reconciles on
      // its own, so the blind safety net runs once a minute.
      final reconcile =
          _officialSource != null &&
          (_lastHint == null ||
              _now().difference(_lastHint!) >= const Duration(seconds: 60));
      if (changed || reconcile) _hint();
    } catch (error) {
      if (current()) {
        if (error is BridgeClientException &&
            error.code == 'account.local_mode') {
          _onlinePaused = true;
          _stop();
          return;
        }
        _lastReply = null;
        if (_scoped) {
          errors.add(switch (error) {
            BridgeClientException(code: 'communities.notAllowed') =>
              'notAllowed',
            BridgeClientException(
              code: 'communities.identityUnavailable' ||
                  'account.reauthorization_required',
            ) =>
              'identityUnavailable',
            FormatException() => 'dataInvalid',
            _ => 'unavailable',
          });
        }
        _failures = (_failures + 1).clamp(1, 5);
        delay = Duration(seconds: 1 << _failures);
      }
    } finally {
      if (current()) {
        _pending = null;
        _schedule(delay, epoch);
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _stop();
    await _events.cancel();
    await _capabilities.cancel();
    await changes.close();
    await errors.close();
  }
}
