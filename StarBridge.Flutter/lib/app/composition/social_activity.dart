import 'dart:async';

import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_client_session.dart';

/// One account-bound wake-up stream per bridge. Contains no identity or content.
final _signals = Expando<StreamController<void>>();
final _lastReply = Expando<DateTime>();
bool socialActivityHealthy(BridgeClientSession session) {
  final last = _lastReply[session];
  return last != null && DateTime.now().difference(last) < const Duration(seconds: 12);
}
StreamController<void> _signal(BridgeClientSession session) =>
    _signals[session] ??= StreamController<void>.broadcast(sync: true);
Stream<void> socialActivityChanges(BridgeClientSession session) => _signal(session).stream;
// Successful idempotent receipt changes unread authority without waiting for a
// remote activity heartbeat. Consumers re-read; no optimistic unread clearing.
void notifySocialReadChanged(BridgeClientSession session) => _signal(session).add(null);

class SocialActivity {
  SocialActivity(this.session) {
    _events = session.events.listen((event) {
      if (event.name == 'account.changed' || event.name == 'bootstrap.invalidated') {
        _epoch++;
        _instance = '';
        _version = -1;
        _lastReply[session] = null;
        unawaited(_pending?.cancel());
        _timer?.cancel();
        if (!_busy) _schedule(Duration.zero);
      }
    });
    _schedule(Duration.zero);
  }
  final BridgeClientSession session;
  late final StreamSubscription<Object?> _events;
  BridgeRequestOperation? _pending;
  Timer? _timer;
  int _epoch = 0, _version = -1, _failures = 0;
  String _instance = '';
  bool _closed = false, _busy = false;

  void _schedule(Duration delay) {
    if (!_closed && session.hostCapabilities.contains('social.wait')) {
      _timer = Timer(delay, _wait);
    }
  }
  Future<void> _wait() async {
    if (_closed || _busy) return;
    _busy = true;
    final epoch = _epoch;
    var delay = const Duration(milliseconds: 100);
    try {
      _pending = session.beginRequest('account.getCurrent', payload: const {'schemaVersion': 1});
      final account = await _pending!.future;
      if (epoch != _epoch || _closed) return;
      if (!hasRelayAccount(account) || account.accountContext == null) {
        _lastReply[session] = null;
        delay = const Duration(seconds: 15);
        return;
      }
      _pending = session.beginRequest('social.wait', accountContext: account.accountContext,
          payload: {'schemaVersion': 1, 'instance': _instance, 'version': _version});
      final reply = await _pending!.future;
      if (_closed || epoch != _epoch) return;
      final instance = reply.payload['instance'], version = reply.payload['version'];
      if (reply.payload['schemaVersion'] != 1 || instance is! String ||
          !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(instance) || version is! int || version < 0) {
        throw const FormatException('Invalid social cursor');
      }
      final changed = instance != _instance || version != _version;
      _instance = instance;
      _version = version;
      _failures = 0;
      _lastReply[session] = DateTime.now();
      if (changed) _signal(session).add(null);
    } catch (_) {
      if (epoch == _epoch) {
        _lastReply[session] = null;
        if (_failures < 5) _failures++;
        delay = Duration(seconds: 1 << _failures);
      }
    } finally {
      _pending = null;
      _busy = false;
      _schedule(epoch == _epoch ? delay : Duration.zero);
    }
  }
  void dispose() {
    _closed = true;
    _lastReply[session] = null;
    _epoch++;
    _timer?.cancel();
    unawaited(_pending?.cancel());
    unawaited(_events.cancel());
  }
}
