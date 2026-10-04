import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/account/account_models.dart';
import '../../features/direct_messages/direct_messages_module.dart';

/// One app-lifetime read-only source. Never shares a cancellable port with chat UI.
final class DirectMessageRefresh {
  DirectMessageRefresh(this.port, this.account) {
    account.addListener(_changed);
    _events = port.invalidations.listen((_) {
      _epoch++;
      unread.value = 0;
      port.cancel();
      _wakePending = true;
      if (!_busy) _schedule(Duration.zero);
    });
    if (port is DirectMessageActivityPort) {
      _activity = (port as DirectMessageActivityPort).changes.listen((_) {
        if (_busy) { _wakePending = true; } else { _schedule(Duration.zero); }
      });
    }
    _schedule(Duration.zero);
  }
  final DirectMessagesPort port;
  final ValueNotifier<int> unread = ValueNotifier(0);
  final ValueListenable<AccountProjection> account;
  late final StreamSubscription<void> _events;
  StreamSubscription<void>? _activity;
  bool _wakePending = false;
  Timer? _timer;
  bool _closed = false, _busy = false;
  int _epoch = 0, _failures = 0;
  bool get _signedIn =>
      account.value.isSignedIn || account.value.isLegacyAccount;

  void _changed() {
    if (_closed) return;
    if (!_signedIn) {
      _epoch++;
      unread.value = 0;
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
      final rows = await port.directory();
      if (!_closed && epoch == _epoch) {
        _failures = 0;
        unread.value = rows.fold(0, (sum, row) => sum + (row.unread < 0 ? 0 : row.unread));
      }
    } catch (_) {
      if (epoch == _epoch && _failures < 3) _failures++;
    } finally {
      _busy = false;
      final wake = _wakePending;
      _wakePending = false;
      _schedule(wake ? Duration.zero : Duration(seconds: 15 * (1 << _failures)));
    }
  }

  void dispose() {
    _closed = true;
    _epoch++;
    _timer?.cancel();
    account.removeListener(_changed);
    unawaited(_events.cancel());
    unawaited(_activity?.cancel());
    port.cancel();
    unawaited(port.close());
    unread.dispose();
  }
}
