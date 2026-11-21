import 'dart:async';

import 'package:flutter/foundation.dart';

import 'account_migration.dart';
import 'account_models.dart';
import 'bridge_account_migration.dart';

// One controller per signed-in account module, shared by the settings card and
// the startup result prompt so both see the same status and the same "shown".
final _shared = Expando<AccountMigrationController>('account-migration');
final _offerChanges = Expando<_OfferSignal>('account-migration-offer');

final class _OfferSignal extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// The migration card's state (account plan item 9). It combines the Host's
/// migration status with the account's own compatibility state: once migrated,
/// the relay keeps the old account retired even with the switch off, so the
/// card stays "migrated" while the status itself is no longer offered.
final class AccountMigrationController
    extends ValueNotifier<AccountMigrationView> {
  AccountMigrationController(
    this._port,
    this._account, {
    this.pollEvery = const Duration(seconds: 2),
    this.pollFor = const Duration(seconds: 30),
    this.slowEvery = const Duration(minutes: 1),
    this.slowFor = const Duration(hours: 1),
  }) : super(const AccountMigrationView.unavailable()) {
    _account.addListener(_accountChanged);
    _accountChanged();
  }

  final AccountMigrationPort _port;
  final ValueListenable<AccountProjection> _account;
  final Duration pollEvery;
  final Duration pollFor;

  /// After the quick polls: one read a minute for at most an hour, so a long
  /// migration still ends on the card and in the result prompt.
  final Duration slowEvery;
  final Duration slowFor;
  Timer? _poll;
  // Counted in polls, not wall time: at most pollFor / pollEvery quick reads,
  // then at most slowFor / slowEvery slow ones.
  int? _polls;
  int _slowPolls = 0;
  bool _slow = false;
  (
    AccountSessionState,
    int,
    AccountCompatibilityIdentityState,
    AccountCompatibilityRelayState,
  )?
  _key;
  int _epoch = 0;
  bool _disposed = false;
  bool busy = false;
  AccountMigrationReading? _last;
  // Bumped by every acknowledge: a read that started before it cannot bring
  // the result back as pending.
  int _acks = 0;
  bool _presenting = false;

  /// The controller shared through [projection]'s account, if one was shared.
  static AccountMigrationController? sharedFor(Object projection) =>
      _shared[projection];

  /// Notifies whenever "offered" changes for the controller shared through
  /// [projection], including one shared later. Lives as long as [projection].
  static Listenable offerChangesFor(Object projection) =>
      _offerChanges[projection] ??= _OfferSignal();

  /// Shares this controller with everything holding the same [projection],
  /// until it is disposed (its creator owns that).
  void shareThrough(Object projection) {
    _sharedThrough = projection;
    _shared[projection] = this;
    _lastOffered = value.offered;
    addListener(_offerChanged);
    _offerChanges[projection]?.ping();
  }

  bool _lastOffered = false;

  void _offerChanged() {
    if (value.offered == _lastOffered) return;
    _lastOffered = value.offered;
    final through = _sharedThrough;
    if (through != null) _offerChanges[through]?.ping();
  }

  Object? _sharedThrough;

  /// Disposed by its owner; a borrower stops listening then.
  bool get disposed => _disposed;

  /// The relay has migrated this account and the Host still has its result.
  bool get resultPending => _last?.resultPending ?? false;

  /// A result dialog from this controller is open.
  bool get presenting => _presenting;

  /// Shows the result at most once at a time, from the card or the startup
  /// prompt, and marks it shown.
  Future<void> present(
    Future<void> Function(AccountMigrationView view) show,
  ) async {
    if (_disposed || _presenting) return;
    _presenting = true;
    try {
      unawaited(acknowledge());
      await show(value);
    } finally {
      _presenting = false;
    }
  }

  void _accountChanged() {
    final account = _account.value;
    final key = (
      account.sessionState,
      account.generation,
      account.compatibility.identityState,
      account.compatibility.relayState,
    );
    if (key == _key) return;
    final sameSession =
        _key != null && _key!.$1 == key.$1 && _key!.$2 == key.$2;
    _key = key;
    if (!sameSession) {
      _epoch++;
      _stopPolling();
      _last = null;
      value = const AccountMigrationView.unavailable();
    }
    if (account.isSignedIn && _port.supported) unawaited(load());
  }

  Future<void> load({bool refresh = false}) =>
      _read(() => _port.read(refresh: refresh));

  Future<void> retry() => _read(_port.retry);

  /// Called when the result is shown, so it is not shown again.
  Future<void> acknowledge() async {
    final reading = _last;
    if (reading == null || !reading.resultPending) return;
    _acks++;
    _last = _withoutPending(reading);
    try {
      await _port.acknowledge();
    } catch (_) {
      // Not marked: the result may be shown once more later. Nothing else.
    }
  }

  Future<void> _read(Future<AccountMigrationReading> Function() read) async {
    if (_disposed) return;
    final epoch = _epoch, acks = _acks;
    busy = true;
    notifyListeners();
    AccountMigrationReading? reading;
    try {
      reading = await read();
    } catch (_) {
      reading = null;
    }
    if (_disposed || epoch != _epoch) return;
    busy = false;
    if (reading != null && reading.resultPending && acks != _acks) {
      reading = _withoutPending(reading);
    }
    if (reading != null) _last = reading;
    value = _project(_last);
    if (value.state == AccountMigrationState.migrating) {
      _startPolling(epoch);
    } else {
      _stopPolling();
    }
  }

  AccountMigrationView _project(AccountMigrationReading? reading) {
    final compatibility = _account.value.compatibility;
    if (reading == null || !reading.available) {
      // The status is not offered (switch off) but the old account stays retired.
      return compatibility.relayState == AccountCompatibilityRelayState.migrated
          ? const AccountMigrationView(
              AccountMigrationState.completed,
              localData: AccountMigrationLocalData.linked,
              resultAvailable: false,
            )
          : const AccountMigrationView.unavailable();
    }
    return switch (reading.state) {
      'completed' => AccountMigrationView(
        AccountMigrationState.completed,
        friends: reading.friends,
        communities: reading.communities,
        merged: reading.merged,
        localData: reading.localData,
      ),
      'failed' => AccountMigrationView(
        reading.recoveryRequired
            ? AccountMigrationState.recoveryRequired
            : AccountMigrationState.failed,
      ),
      'migrating' => AccountMigrationView(
        AccountMigrationState.migrating,
        stillWorking: _pollExpired,
      ),
      // Nothing to migrate yet: an unlinked account migrates through the old
      // account sign-in; a linked one is migrated by the relay on its next read.
      _ =>
        compatibility.identityState == AccountCompatibilityIdentityState.linked
            ? AccountMigrationView(
                AccountMigrationState.migrating,
                stillWorking: _pollExpired,
              )
            : const AccountMigrationView(AccountMigrationState.notLinked),
    };
  }

  int get _pollLimit => pollEvery.inMicroseconds <= 0
      ? 0
      : pollFor.inMicroseconds ~/ pollEvery.inMicroseconds;

  bool get _pollExpired => _polls != null && _polls! >= _pollLimit;

  int get _slowLimit => slowEvery.inMicroseconds <= 0
      ? 0
      : slowFor.inMicroseconds ~/ slowEvery.inMicroseconds;

  void _startPolling(int epoch) {
    _polls ??= 0;
    if (!_pollExpired) {
      _poll ??= Timer.periodic(pollEvery, (_) {
        if (epoch != _epoch || busy) return;
        _polls = (_polls ?? 0) + 1;
        unawaited(load());
      });
      return;
    }
    if (!_slow) {
      _poll?.cancel();
      _poll = null;
      _slow = true;
    }
    if (_slowPolls >= _slowLimit) {
      // Bounded: after this the card keeps "still working" until the next
      // compatibility change or sign-in reads again. No endless polling.
      _poll?.cancel();
      _poll = null;
      return;
    }
    _poll ??= Timer.periodic(slowEvery, (_) {
      if (epoch != _epoch || busy) return;
      _slowPolls++;
      unawaited(load());
    });
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
    _polls = null;
    _slowPolls = 0;
    _slow = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _stopPolling();
    final through = _sharedThrough;
    if (through != null && identical(_shared[through], this)) {
      _shared[through] = null;
      if (_lastOffered) _offerChanges[through]?.ping();
    }
    _account.removeListener(_accountChanged);
    super.dispose();
  }
}

AccountMigrationReading _withoutPending(AccountMigrationReading reading) =>
    AccountMigrationReading(
      available: reading.available,
      state: reading.state,
      friends: reading.friends,
      communities: reading.communities,
      merged: reading.merged,
      recoveryRequired: reading.recoveryRequired,
      localData: reading.localData,
    );
