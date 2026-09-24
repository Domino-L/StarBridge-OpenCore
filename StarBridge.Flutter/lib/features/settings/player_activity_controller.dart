import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import 'notification_settings_models.dart';

typedef PlayerActivityRequest = Future<Map<String, Object?>> Function(
  String name,
  Map<String, Object?> payload,
);

class PlayerActivityValue {
  const PlayerActivityValue(
    this.settings,
    this.position,
    this.revision,
    this.writable,
  );
  final PlayerActivityNotificationSettings settings;
  final int position;
  final String revision;
  final bool writable;
  static PlayerActivityValue parse(Map<String, Object?> b) {
    const flags = [
      'enabled',
      'online',
      'offline',
      'startedGame',
      'stoppedGame',
      'backgroundOnly',
      'reduceInGame',
      'writable',
    ];
    final scope = b['scope'],
        position = b['position'],
        revision = b['revision'];
    if (b.length != 12 ||
        b['schemaVersion'] != 1 ||
        flags.any((k) => b[k] is! bool) ||
        scope is! int ||
        scope < 0 ||
        scope > 7 ||
        position is! int ||
        position < 0 ||
        position > 3 ||
        revision is! String ||
        !(revision == 'missing' ||
            RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(revision))) {
      throw const FormatException('Invalid player activity settings');
    }
    return PlayerActivityValue(
      PlayerActivityNotificationSettings(
        enabled: b['enabled'] as bool,
        // Legacy presentation slot: WPF bit 2 is COMMUNITY membership, not RSI affiliation.
        includeOfficialFleet: scope & 2 != 0,
        includeFriends: scope & 4 != 0,
        includeCurrentRoom: scope & 1 != 0,
        notifyOnline: b['online'] as bool,
        notifyOffline: b['offline'] as bool,
        notifyGameStarted: b['startedGame'] as bool,
        notifyGameStopped: b['stoppedGame'] as bool,
        backgroundOnly: b['backgroundOnly'] as bool,
        reduceInGame: b['reduceInGame'] as bool,
      ),
      position,
      revision,
      b['writable'] as bool,
    );
  }
}

/// Dialog lifetime only. No poller, account bootstrap, optimistic persistence or retry of writes.
class PlayerActivityController extends ChangeNotifier {
  PlayerActivityController(this._request, {required this.generation});
  factory PlayerActivityController.bridge(BridgeClientSession session) =>
      PlayerActivityController((name, payload) async {
        if (!session.hostCapabilities.contains(name)) {
          throw StateError('Player activity capability unavailable');
        }
        return (await session.request(name, payload: payload)).payload;
      }, generation: () => session.activeGeneration);
  final PlayerActivityRequest _request;
  final int Function() generation;
  PlayerActivityValue? current;
  bool busy = false, failed = false, _disposed = false;
  String? testResult;
  int? _readGeneration;
  bool get canEdit =>
      !busy &&
      !failed &&
      current?.writable == true &&
      _readGeneration == generation();
  Future<bool> refresh() =>
      _run('playerActivity.read', const {'schemaVersion': 1});
  Future<bool> save(PlayerActivityNotificationSettings settings, int position) {
    if (!canEdit) return Future.value(false);
    return _run('playerActivity.save', {
      'schemaVersion': 1,
      'expectedRevision': current!.revision,
      'enabled': settings.enabled,
      'scope':
          (settings.includeOfficialFleet ? 2 : 0) |
          (settings.includeFriends ? 4 : 0) |
          (settings.includeCurrentRoom ? 1 : 0),
      'position': position,
      'online': settings.notifyOnline,
      'offline': settings.notifyOffline,
      'startedGame': settings.notifyGameStarted,
      'stoppedGame': settings.notifyGameStopped,
      'backgroundOnly': settings.backgroundOnly,
      'reduceInGame': settings.reduceInGame,
    });
  }

  Future<bool> test() {
    if (!canEdit) return Future.value(false);
    return _run('playerActivity.test', const {'schemaVersion': 1});
  }

  Future<bool> _run(String name, Map<String, Object?> payload) async {
    if (_disposed || busy) return false;
    final requestedGeneration = generation();
    busy = true;
    failed = false;
    testResult = null;
    notifyListeners();
    try {
      final body = await _requestWithReadRecovery(
        name,
        payload,
        requestedGeneration,
      );
      if (_disposed) return false;
      if (generation() != requestedGeneration) {
        current = null;
        throw StateError('Stale session');
      }
      if (name == 'playerActivity.test') {
        if (body.length != 3 ||
            body['schemaVersion'] != 1 ||
            body['submitted'] is! bool ||
            body['reason'] is! String) {
          throw const FormatException('Invalid test result');
        }
        testResult = body['submitted'] == true ? 'submitted' : 'suppressed';
      } else {
        current = PlayerActivityValue.parse(body);
        _readGeneration = requestedGeneration;
      }
      return true;
    } on Object {
      if (!_disposed) {
        // Delivery failure does not invalidate an already verified settings snapshot.
        // Writes still fail closed: their outcome must never be retried implicitly.
        if (name == 'playerActivity.test' &&
            generation() == requestedGeneration &&
            _readGeneration == requestedGeneration &&
            current != null) {
          testResult = 'unavailable';
        } else {
          failed = true;
        }
      }
      return false;
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<Map<String, Object?>> _requestWithReadRecovery(
    String name,
    Map<String, Object?> payload,
    int requestedGeneration,
  ) async {
    for (var attempt = 0; ; attempt++) {
      if (_disposed || generation() != requestedGeneration) {
        throw StateError('Stale settings read');
      }
      try {
        return await _request(name, payload);
      } on BridgeClientException catch (error) {
        final transient =
            error.retryable ||
            error.code == 'playerActivity.storage_unavailable' ||
            error.code == 'playerActivity.not_ready';
        if (name != 'playerActivity.read' ||
            !transient ||
            attempt >= 2 ||
            _disposed ||
            generation() != requestedGeneration) {
          rethrow;
        }
        // Keep the loading state throughout a short, bounded recovery window.
        await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
