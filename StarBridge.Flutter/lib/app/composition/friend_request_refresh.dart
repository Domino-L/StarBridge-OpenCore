import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/account/account_models.dart';
import '../../features/friends/friends_module.dart';
import '../../shared/diagnostics/loading_read_scope.dart';

/// App-owned request count. Its separate read-only port cannot cancel a search
/// or overwrite the friends page. Existing social activity wakes this owner.
final class FriendRequestRefresh {
  FriendRequestRefresh(this.port, this.account) {
    account.addListener(_accountChanged);
    _invalidations = port.invalidations.listen((_) {
      _epoch++;
      // Avatar refresh/lost pipe is not a completed request. Account changes
      // and confirmed request/permission readback own clearing this count.
      port.cancelPending();
      _wake = true;
      if (!_busy) _schedule(Duration.zero);
    });
    if (port is FriendsActivityPort) {
      _activity = (port as FriendsActivityPort).changes.listen((_) {
        _wake = true;
        if (!_busy) _schedule(Duration.zero);
      });
    }
    _accountChanged();
  }
  final FriendsPort port;
  final ValueListenable<AccountProjection> account;
  final count = ValueNotifier(0);
  late final StreamSubscription<void> _invalidations;
  StreamSubscription<void>? _activity;
  Timer? _timer;
  int _epoch = 0, _failures = 0;
  int? _generation;
  bool _closed = false, _busy = false, _wake = false;
  bool get _signedIn =>
      account.value.isSignedIn || account.value.isLegacyAccount;
  void _accountChanged() {
    if (_closed) return;
    final next = _signedIn ? account.value.generation : null;
    if (next != _generation) {
      _generation = next;
      _epoch++;
      count.value = 0;
      port.cancelPending();
      _timer?.cancel();
      _wake = true;
    }
    if (!_busy && !(_timer?.isActive ?? false)) _schedule(Duration.zero);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (!_closed && _signedIn) {
      _timer = Timer(delay, () => backgroundLoadingRead(_read));
    }
  }

  Future<void> _read() async {
    if (_closed || _busy || !_signedIn) return;
    _busy = true;
    _wake = false;
    final epoch = _epoch;
    try {
      final result = await port.read();
      if (_closed || epoch != _epoch) return;
      if (result.state == FriendsReadState.ready &&
          result.snapshot != null &&
          result.snapshot!.query == null) {
        _failures = 0;
        count.value =
            result.snapshot!.groups[FriendsSection.incoming]?.length ?? 0;
      } else if (result.state == FriendsReadState.signedOut ||
          result.failure == 'identityUnavailable' ||
          result.failure == 'notAllowed') {
        count.value = 0;
      } else {
        _failures = (_failures + 1).clamp(0, 3);
      }
    } on Object {
      if (epoch == _epoch) _failures = (_failures + 1).clamp(0, 3);
    } finally {
      _busy = false;
      _schedule(
        _wake ? Duration.zero : Duration(seconds: 15 * (1 << _failures)),
      );
    }
  }

  void dispose() {
    _closed = true;
    _epoch++;
    _timer?.cancel();
    account.removeListener(_accountChanged);
    unawaited(_invalidations.cancel());
    unawaited(_activity?.cancel());
    port.cancelPending();
    unawaited(port.close());
    count.dispose();
  }
}
