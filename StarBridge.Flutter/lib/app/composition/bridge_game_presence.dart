import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../shell/chrome/shell_chrome_projection.dart';

/// A local, optional observation: it never publishes presence or records playtime.
final class BridgeGamePresence extends ValueNotifier<GamePresenceState> {
  BridgeGamePresence(
    this._session, {
    this.pollInterval = const Duration(seconds: 5),
  }) : super(GamePresenceState.unknown) {
    if (_session.hostCapabilities.contains('host.gamePresence')) {
      unawaited(_read());
    }
  }

  final BridgeClientSession _session;
  final Duration pollInterval;
  Timer? _timer;
  bool _disposed = false;
  String? _version;
  String? get version => value == GamePresenceState.running ? _version : null;

  Future<void> _read() async {
    try {
      final response = await _session.request(
        'host.getGamePresence',
        timeout: const Duration(seconds: 5),
      );
      if (_disposed) return;
      final rawVersion = response.payload['version'];
      _version =
          rawVersion is String &&
              RegExp(r'^[A-Z0-9_-]{2,32}$').hasMatch(rawVersion)
          ? rawVersion
          : null;
      value = response.payload['schemaVersion'] != 1
          ? GamePresenceState.unknown
          : switch (response.payload['state']) {
              'running' => GamePresenceState.running,
              'notRunning' => GamePresenceState.notRunning,
              _ => GamePresenceState.unknown,
            };
    } on Object {
      if (!_disposed) {
        _version = null;
        value = GamePresenceState.unknown;
      }
    } finally {
      if (!_disposed) _timer = Timer(pollInterval, () => unawaited(_read()));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
