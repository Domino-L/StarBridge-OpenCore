import 'dart:async';

import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_client_session.dart';

/// One cancellable server wait while organization surfaces have subscribers.
/// Heartbeat replies do not reload content. Reconnects reconcile once.
final class CommunityActivity {
  CommunityActivity(this.session) {
    changes = StreamController<void>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
    _events = session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _stop();
        if (changes.hasListener) _start();
      }
    });
  }
  final BridgeClientSession session;
  late final StreamController<void> changes;
  late final StreamSubscription<Object?> _events;
  BridgeRequestOperation? _pending;
  Timer? _timer;
  DateTime? _lastReply;
  bool _presenceEvents = false;
  int _epoch = 0, _version = -1, _failures = 0;
  String _instance = '';
  bool _closed = false;
  bool get healthy =>
      _presenceEvents &&
      _lastReply != null &&
      DateTime.now().difference(_lastReply!) < const Duration(seconds: 12);

  void _start() => _schedule(Duration.zero, _epoch);
  void _schedule(Duration delay, int epoch) {
    if (!_closed &&
        epoch == _epoch &&
        changes.hasListener &&
        session.hostCapabilities.contains('communities.wait')) {
      _timer?.cancel();
      _timer = Timer(delay, () => _wait(epoch));
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
  }

  Future<void> _wait(int epoch) async {
    var delay = const Duration(milliseconds: 150);
    bool current() => !_closed && epoch == _epoch && changes.hasListener;
    try {
      _pending = session.beginRequest(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      final account = await _pending!.future;
      if (!current()) return;
      if (!hasRelayAccount(account) || account.accountContext == null) {
        _lastReply = null;
        delay = const Duration(seconds: 15);
        return;
      }
      _pending = session.beginRequest(
        'communities.wait',
        accountContext: account.accountContext,
        payload: {
          'schemaVersion': 1,
          'instance': _instance,
          'version': _version,
        },
      );
      final reply = await _pending!.future;
      if (!current()) return;
      final instance = reply.payload['instance'],
          version = reply.payload['version'];
      if (reply.payload['schemaVersion'] != 1 ||
          instance is! String ||
          !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(instance) ||
          version is! int ||
          version < 0 ||
          instance == _instance && version < _version) {
        throw const FormatException('Invalid organization cursor');
      }
      final changed =
          instance != _instance || version != _version || _failures > 0;
      _instance = instance;
      _version = version;
      _failures = 0;
      _lastReply = DateTime.now();
      _presenceEvents = reply.payload['presenceEvents'] == true;
      if (changed) changes.add(null);
    } catch (_) {
      if (current()) {
        _lastReply = null;
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
    await changes.close();
  }
}
