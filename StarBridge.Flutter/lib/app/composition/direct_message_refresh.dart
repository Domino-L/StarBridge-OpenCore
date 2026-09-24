import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/account/account_models.dart';
import '../../features/direct_messages/direct_messages_module.dart';

/// One app-lifetime read-only source. Never shares a cancellable port with chat UI.
final class DirectMessageRefresh {
  DirectMessageRefresh(this.port, this.account) {
    account.addListener(_changed);
    _events = port.invalidations.listen((_) => _changed());
    _schedule(Duration.zero);
  }
  final DirectMessagesPort port;
  final ValueListenable<AccountProjection> account;
  late final StreamSubscription<void> _events;
  Timer? _timer;
  bool _closed = false, _busy = false;
  int _epoch = 0, _failures = 0;
  bool get _signedIn =>
      account.value.isSignedIn || account.value.isLegacyAccount;

  void _changed() {
    if (_closed) return;
    if (!_signedIn) {
      _epoch++;
      port.cancel();
      _timer?.cancel();
    } else if (!_busy && !(_timer?.isActive ?? false)) {
      _schedule(Duration.zero);
    }
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (!_closed && _signedIn) _timer = Timer(delay, _read);
  }

  Future<void> _read() async {
    if (_closed || _busy || !_signedIn) return;
    _busy = true;
    final epoch = _epoch;
    try {
      await port.directory();
      if (epoch == _epoch) _failures = 0;
    } catch (_) {
      if (epoch == _epoch && _failures < 3) _failures++;
    } finally {
      _busy = false;
      _schedule(Duration(seconds: 15 * (1 << _failures)));
    }
  }

  void dispose() {
    _closed = true;
    _epoch++;
    _timer?.cancel();
    account.removeListener(_changed);
    unawaited(_events.cancel());
    port.cancel();
    unawaited(port.close());
  }
}
