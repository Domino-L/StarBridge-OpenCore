import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridge/bridge_client_session.dart';
import '../bridge/bridge_envelope.dart';
import 'menu_hotkey_port.dart';
import 'menu_shortcut_settings.dart';
import 'menu_settings_read.dart';

/// One subscription to the Host's existing raw-input owner. This class never
/// reads keyboard state or opens a native window by itself.
final class BridgeMenuHotkeys
    implements MenuHotkeyPort, MenuShortcutSettingsPort {
  BridgeMenuHotkeys(
    this.session, {
    required this.activation,
    required this.isActive,
  });
  final BridgeClientSession session;
  final Listenable activation;
  final bool Function() isActive;
  StreamSubscription<BridgeEnvelope>? _events;
  int Function()? _nextClient;
  Future<void> Function(MenuHotkeyIntent)? _onIntent;
  void Function()? _onRevoked;
  Future<void> _work = Future.value();
  int? _client, _generation;
  int _authorityEpoch = 0;
  bool _disposed = false, _attached = false;

  @override
  void initialize(
    int Function() nextClient,
    Future<void> Function(MenuHotkeyIntent) onIntent,
    void Function() onRevoked,
  ) {
    if (_disposed || _events != null) return;
    _nextClient = nextClient;
    _onIntent = onIntent;
    _onRevoked = onRevoked;
    _events = session.events.listen(_event);
    activation.addListener(_changed);
    _changed();
  }

  void _changed() {
    if (_disposed) return;
    // Synchronous revocation: no event queued behind an account change may open
    // a window while the serialized native detach is still in flight.
    if (!isActive() || _generation != session.activeGeneration) {
      _authorityEpoch++;
      _attached = false;
      if (_client != null) _onRevoked?.call();
    }
    _work = _work.then((_) => _synchronize());
  }

  Future<void> _synchronize() async {
    if (_disposed) return;
    if (!isActive()) {
      final old = _client;
      _client = null;
      _generation = null;
      if (old != null) await _detach(old);
      return;
    }
    if (_attached && _generation == session.activeGeneration) return;
    final client = _nextClient!(), generation = session.activeGeneration;
    final epoch = _authorityEpoch;
    _client = client;
    _generation = generation;
    try {
      await session.request(
        'menuHotkey.attach',
        payload: {
          'schemaVersion': 1,
          'client': client,
          'binding': 'Alt+M',
          'enabled': true,
          'closeWithHotkey': true,
        },
        timeout: const Duration(seconds: 3),
      );
      if (!_disposed &&
          epoch == _authorityEpoch &&
          _client == client &&
          session.activeGeneration == generation &&
          isActive()) {
        _attached = true;
      } else {
        await _detach(client);
      }
    } on Object {
      /* Button opening remains available; never fall back to demo. */
    }
  }

  void _event(BridgeEnvelope event) {
    if (_disposed ||
        !_attached ||
        !isActive() ||
        event.name != 'menuHotkey.intent' ||
        event.sessionGeneration != _generation ||
        session.activeGeneration != _generation) {
      return;
    }
    final p = event.payload;
    if (p['schemaVersion'] != 1 ||
        p['client'] != _client ||
        !const {'open', 'close'}.contains(p['action']) ||
        p['request'] is! int ||
        p['targetWindow'] is! int ||
        p['targetProcessId'] is! int) {
      return;
    }
    unawaited(
      _onIntent!(
        MenuHotkeyIntent(
          p['action'] as String,
          p['request'] as int,
          p['targetWindow'] as int,
          p['targetProcessId'] as int,
        ),
      ).catchError((Object _) {}),
    );
  }

  @override
  Future<void> window(int request, String phase, int handle) async {
    final generation = session.activeGeneration, epoch = _authorityEpoch;
    final owner = _client;
    await _work;
    final client = _client;
    if (_disposed ||
        !_attached ||
        client == null ||
        epoch != _authorityEpoch ||
        generation != session.activeGeneration ||
        (owner != null && owner != client) ||
        !isActive() ||
        _generation != session.activeGeneration) {
      return;
    }
    try {
      await session.request(
        'menuHotkey.window',
        payload: {
          'schemaVersion': 1,
          'client': client,
          'request': request,
          'phase': phase,
          'window': handle,
        },
        timeout: const Duration(seconds: 3),
      );
    } on Object {
      /* No shortcut close authority is assumed after a failed ack. */
    }
  }

  Future<void> _detach(int client) async {
    try {
      await session.request(
        'menuHotkey.detach',
        payload: {'schemaVersion': 1, 'client': client},
        timeout: const Duration(seconds: 3),
      );
    } on Object {
      /* Host generation change already revokes the old lease. */
    }
  }

  @override
  Future<MenuShortcutSettings> readShortcut() => _settings(null);
  @override
  Future<MenuShortcutSettings> saveShortcut(MenuShortcutSettings value) =>
      _settings(value);

  Future<MenuShortcutSettings> _settings(MenuShortcutSettings? value) {
    final result = Completer<MenuShortcutSettings>();
    final epoch = _authorityEpoch, generation = session.activeGeneration;
    _work = _work.then((_) async {
      try {
        if (_disposed ||
            epoch != _authorityEpoch ||
            generation != session.activeGeneration ||
            !isActive()) {
          throw const BridgeClientException('menuHotkey.session_unavailable');
        }
        if (!_attached) await _synchronize();
        if (!_attached || _client == null) {
          throw const BridgeClientException('menuHotkey.unavailable');
        }
        final reply = value == null
            ? await readMenuSettings(
                session,
                'menuHotkey.settings.get',
                unavailableCode: 'menuHotkey.session_unavailable',
                payload: {'schemaVersion': 1, 'client': _client},
                isCurrent: () =>
                    !_disposed &&
                    epoch == _authorityEpoch &&
                    generation == session.activeGeneration &&
                    _attached &&
                    isActive(),
              )
            : await session.request(
                'menuHotkey.settings.update',
                payload: {
                  'schemaVersion': 1,
                  'client': _client,
                  'expectedRevision': value.revision,
                  'binding': value.binding,
                  'enabled': value.enabled,
                  'closeWithHotkey': value.closeWithHotkey,
                },
                timeout: const Duration(seconds: 3),
              );
        if (_disposed ||
            epoch != _authorityEpoch ||
            generation != session.activeGeneration ||
            !isActive()) {
          throw const BridgeClientException('menuHotkey.session_unavailable');
        }
        result.complete(MenuShortcutSettings.parse(reply.payload));
      } on Object catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _attached = false;
    activation.removeListener(_changed);
    unawaited(_events?.cancel());
    if (_client case final client?) unawaited(_detach(client));
    _onIntent = null;
  }
}
