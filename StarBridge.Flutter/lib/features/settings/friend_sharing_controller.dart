import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_client_session.dart';

class FriendSharingController extends ChangeNotifier {
  FriendSharingController(this.session) {
    _events = session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _epoch++;
        _owner = null;
        snapshot = null;
        busy = false;
        _refreshing = false;
        error = null;
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
  String? get accountKey => _owner;
  String state = 'inactive';
  Map<String, Object?>? snapshot;
  int get fields => snapshot?['fields'] as int? ?? 0;
  bool get canEdit => !busy && snapshot != null && error == null;

  static Map<String, Object?> validate(Map<String, Object?> body) {
    if (body.length != 2 ||
        !const {'active', 'inactive', 'unconfirmed'}.contains(body['state'])) {
      throw const FormatException();
    }
    final value = (body['snapshot'] as Map).cast<String, Object?>();
    final revision = value['revision'];
    final fields = value['fields'];
    if (value.length != 5 ||
        value['schemaVersion'] != 1 ||
        revision is! int ||
        revision < 0 ||
        (fields != null && (fields is! int || fields < 0 || fields > 63))) {
      throw const FormatException();
    }
    if (revision == 0) {
      if (fields != null ||
          value['operationId'] != null ||
          value['appliedAt'] != null) {
        throw const FormatException();
      }
    } else if (fields == null ||
        value['operationId'] is! String ||
        !RegExp(r'^[0-9a-fA-F]{32}$')
            .hasMatch(value['operationId'] as String) ||
        value['appliedAt'] is! String ||
        DateTime.tryParse(value['appliedAt'] as String) == null) {
      throw const FormatException();
    }
    return value;
  }

  Future<Map<String, Object?>> _request(
    String name,
    Map<String, Object?> payload,
    int epoch,
  ) async {
    if (!session.hostCapabilities.contains('friendSharing.settings')) {
      throw const BridgeClientException('host.capability_missing');
    }
    final account = await session.request(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
    );
    if (_closed || epoch != _epoch || !hasRelayAccount(account)) {
      throw const BridgeClientException('friendsSharing.account_changed');
    }
    final owner =
        '${account.sessionGeneration}:${jsonEncode(account.accountContext?.toJson())}';
    if ((_owner != null && owner != _owner) ||
        (name == 'friendSharing.save' && _owner == null)) {
      snapshot = null;
      _owner = null;
      throw const BridgeClientException('friendsSharing.account_changed');
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
      throw const BridgeClientException('friendsSharing.account_changed');
    }
    _owner = owner;
    return response.payload;
  }

  Future<void> refresh() async {
    if (_closed || busy || _refreshing) return;
    final epoch = _epoch;
    _refreshing = true;
    busy = snapshot == null;
    if (busy) notifyListeners();
    try {
      final body = await _request('friendSharing.read', const {
        'schemaVersion': 1,
      }, epoch);
      final value = validate(body);
      if (_closed || epoch != _epoch) return;
      snapshot = value;
      state = body['state'] as String;
      error = null;
    } catch (e) {
      if (!_closed && epoch == _epoch) {
        error = e is BridgeClientException
            ? e.code
            : 'friendsSharing.invalid_response';
      }
    } finally {
      if (!_closed && epoch == _epoch) {
        busy = false;
        _refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> change(int bit, bool enabled) async {
    if (!canEdit || !const {1, 2, 4, 8, 16, 32}.contains(bit)) return;
    final next = enabled ? fields | bit : fields & ~bit;
    await saveFields(next);
  }

  Future<void> saveFields(int next) async {
    if (!canEdit || next < 0 || next > 63) return;
    // A save supersedes older background reads, including their errors.
    final epoch = ++_epoch, revision = snapshot!['revision'] as int;
    _refreshing = false;
    final random = Random.secure();
    final operation = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    busy = true;
    notifyListeners();
    var failed = false;
    try {
      final body = await _request('friendSharing.save', {
        'schemaVersion': 1,
        'expectedRevision': revision,
        'operationId': operation,
        'fields': next,
      }, epoch);
      final value = validate(body);
      if (value['revision'] != revision + 1 ||
          value['operationId'] != operation ||
          value['fields'] != next) {
        throw const FormatException();
      }
      if (_closed || epoch != _epoch) return;
      snapshot = value;
      state = body['state'] as String;
      error = null;
    } catch (e) {
      failed = true;
      if (!_closed && epoch == _epoch) {
        error = e is BridgeClientException
            ? e.code
            : 'friendsSharing.write_unconfirmed';
      }
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
