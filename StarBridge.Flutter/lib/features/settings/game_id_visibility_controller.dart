import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_client_session.dart';

class GameIdVisibilityController extends ChangeNotifier {
  GameIdVisibilityController(this.session) {
    _events = session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _epoch++;
        _owner = null;
        snapshot = null;
        busy = false;
        _refreshing = false;
        notifyListeners();
        unawaited(refresh());
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
    unawaited(refresh());
  }
  final BridgeClientSession session;
  late final StreamSubscription _events;
  late final Timer _timer;
  bool busy = false, _closed = false;
  bool _refreshing = false;
  int _epoch = 0;
  String? _owner, error;
  Map<String, Object?>? snapshot;
  int get locations => snapshot?['locations'] as int? ?? 0;
  bool get canEdit =>
      !busy && error == null && snapshot?['canConfigure'] == true;

  static Map<String, Object?> validate(Map<String, Object?> value) {
    final revision = value['revision'],
        locations = value['locations'],
        stamp = value['identityStamp'];
    if (value.length != 5 ||
        value['schemaVersion'] != 1 ||
        revision is! int ||
        revision < 0 ||
        locations is! int ||
        locations < 0 ||
        locations > 15 ||
        value['canConfigure'] is! bool ||
        stamp is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(stamp) ||
        value['canConfigure'] == false && locations != 15) {
      throw const FormatException();
    }
    return Map.unmodifiable(value);
  }

  Future<Map<String, Object?>> _request(
    String name,
    Map<String, Object?> payload,
    int epoch,
  ) async {
    if (!session.hostCapabilities.contains('gameIdVisibility.settings')) {
      throw const BridgeClientException('host.capability_missing');
    }
    final account = await session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    if (_closed || epoch != _epoch || !hasRelayAccount(account)) {
      throw const BridgeClientException('gameId.account_changed');
    }
    final owner =
        '${account.sessionGeneration}:${jsonEncode(account.accountContext?.toJson())}';
    if ((_owner != null && _owner != owner) ||
        (name.endsWith('.save') && _owner == null)) {
      snapshot = null;
      _owner = null;
      throw const BridgeClientException('gameId.account_changed');
    }
    final response = await session.request(
      name,
      payload: payload,
      accountContext: account.accountContext,
    );
    if (_closed ||
        epoch != _epoch ||
        response.sessionGeneration != account.sessionGeneration ||
        jsonEncode(response.accountContext?.toJson()) !=
            jsonEncode(account.accountContext?.toJson())) {
      throw const BridgeClientException('gameId.account_changed');
    }
    _owner = owner;
    return validate(response.payload);
  }

  Future<void> refresh() async {
    if (_closed || busy || _refreshing) return;
    final epoch = _epoch;
    _refreshing = true;
    busy = snapshot == null;
    if (busy) notifyListeners();
    try {
      final value = await _request('gameIdVisibility.read', const {
        'schemaVersion': 1,
      }, epoch);
      if (!_closed && epoch == _epoch) {
        snapshot = value;
        error = null;
      }
    } catch (_) {
      if (!_closed && epoch == _epoch) error = 'unavailable';
    } finally {
      if (!_closed && epoch == _epoch) {
        busy = false;
        _refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> change(int bit, bool enabled) async {
    if (!canEdit || !const {1, 2, 4, 8}.contains(bit)) return;
    final next = enabled ? locations | bit : locations & ~bit;
    await saveLocations(next);
  }

  Future<void> saveLocations(int next) async {
    if (!canEdit || next < 0 || next > 15) return;
    // A save supersedes older background reads, including their errors.
    final epoch = ++_epoch, before = snapshot!;
    _refreshing = false;
    busy = true;
    notifyListeners();
    var failed = false;
    try {
      final value = await _request('gameIdVisibility.save', {
        'schemaVersion': 1,
        'expectedRevision': before['revision'],
        'identityStamp': before['identityStamp'],
        'locations': next,
      }, epoch);
      if (value['locations'] != next ||
          value['revision'] != (before['revision'] as int) + 1 ||
          value['identityStamp'] != before['identityStamp']) {
        throw const FormatException();
      }
      if (!_closed && epoch == _epoch) {
        snapshot = value;
        error = null;
      }
    } catch (_) {
      failed = true;
      if (!_closed && epoch == _epoch) error = 'unconfirmed';
    } finally {
      if (!_closed && epoch == _epoch) {
        busy = false;
        notifyListeners();
        if (failed) unawaited(refresh());
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    _timer.cancel();
    unawaited(_events.cancel());
    super.dispose();
  }
}
