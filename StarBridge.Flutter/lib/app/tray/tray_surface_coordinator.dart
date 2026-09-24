import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../presence/manual_presence.dart';
import 'tray_surface_snapshot.dart';

/// Main-isolate owner. Existing modules remain the only command implementations.
class TraySurfaceCoordinator {
  TraySurfaceCoordinator({
    required this.snapshot,
    this.toggleOverlay,
    this.openOverlaySettings,
    this.setPresence,
    this.refresh,
  }) {
    _channel.setMethodCallHandler(_action);
    snapshot.addListener(_changed);
    _changed();
  }
  static const _channel = MethodChannel('starbridge/tray-primary');
  final ValueListenable<TraySurfaceSnapshot> snapshot;
  final Future<void> Function()? toggleOverlay, openOverlaySettings;
  final Future<void> Function()? refresh;
  final Future<void> Function(PresenceVisibility mode)? setPresence;
  bool _disposed = false, _publishing = false, _dirty = false, _busy = false;
  void _changed() {
    _dirty = true;
    unawaited(_publish());
  }

  Future<void> _publish() async {
    if (_disposed || _publishing) return;
    _publishing = true;
    try {
      while (!_disposed && _dirty) {
        _dirty = false;
        await _channel.invokeMethod<void>('configure', snapshot.value.toMap());
      }
    } on Object {
      /* Native fallback keeps Open/Exit available if unsupported. */
    } finally {
      _publishing = false;
    }
  }

  Future<Object?> _action(MethodCall call) async {
    if (!_disposed && call.method == 'refresh') {
      await refresh?.call();
      return null;
    }
    final data = call.arguments;
    if (_disposed ||
        _busy ||
        call.method != 'action' ||
        data is! Map ||
        data['scope'] != snapshot.value.scope) {
      throw PlatformException(code: 'tray.context_changed');
    }
    _busy = true;
    try {
      switch (data['action']) {
        case 'toggleOverlay':
          if (!snapshot.value.canToggleOverlay || toggleOverlay == null) {
            throw PlatformException(code: 'tray.unavailable');
          }
          await toggleOverlay!();
        case 'overlaySettings':
          if (openOverlaySettings == null) {
            throw PlatformException(code: 'tray.unavailable');
          }
          await openOverlaySettings!();
        case 'presence':
          final mode = PresenceVisibility.values
              .where((v) => v.name == data['mode'])
              .firstOrNull;
          if (!snapshot.value.canChangePresence ||
              setPresence == null ||
              mode == null) {
            throw PlatformException(code: 'tray.unavailable');
          }
          await setPresence!(mode);
        default:
          throw PlatformException(code: 'tray.invalid_action');
      }
      if (_disposed) throw PlatformException(code: 'tray.unavailable');
      if (data['scope'] != snapshot.value.scope) {
        throw PlatformException(code: 'tray.context_changed');
      }
      return snapshot.value.toMap();
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    snapshot.removeListener(_changed);
    _channel.setMethodCallHandler(null);
    unawaited(_channel.invokeMethod<void>('detach').catchError((Object _) {}));
  }
}
