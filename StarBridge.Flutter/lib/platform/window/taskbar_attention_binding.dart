import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Count-only, application-lifetime projection. Focus, popups and delivery
/// preferences are not read receipts. No new business polling lives here.
/// Share one scope across replacements within a single application lifetime.
/// Independent application lifetimes must not suppress each other's updates.
final class TaskbarAttentionScope {
  Object? _active;
}

final class TaskbarAttentionBinding {
  TaskbarAttentionBinding({
    required this.scope,
    required List<Listenable> changes,
    required this.pending,
    required this.reduceMotion,
    this.publish,
  }) : _changes = Listenable.merge(changes) {
    scope._active = _owner;
    _changes.addListener(_changed);
    _changed();
  }
  static const _channel = MethodChannel('starbridge/application-lifecycle');
  final TaskbarAttentionScope scope;
  final Object _owner = Object();
  final Listenable _changes;
  final bool Function() pending, reduceMotion;
  final Future<void> Function(Map<String, Object?>)? publish;
  Map<String, Object?>? _last;
  bool _disposed = false, _publishing = false, _dirty = false;
  void _changed() {
    final next = <String, Object?>{
      'pending': pending(),
      'reduceMotion': reduceMotion(),
    };
    if (mapEquals(next, _last)) return;
    _last = next;
    _dirty = true;
    unawaited(_flush());
  }

  Future<void> _flush() async {
    if (_publishing || _disposed) return;
    _publishing = true;
    try {
      while (_dirty && !_disposed) {
        _dirty = false;
        await _send(_last!);
      }
    } on Object {
      // Older Runner versions may not provide this optional presentation seam.
      _last = null;
    } finally {
      _publishing = false;
      if (_disposed) {
        await _send(const {'pending': false, 'reduceMotion': true})
            .catchError((Object _) {});
      }
    }
  }

  Future<void> _send(Map<String, Object?> value) async {
    if (!identical(_owner, scope._active)) return;
    try {
      if (publish != null) {
        await publish!(value);
      } else {
        await _channel.invokeMethod<void>('setTaskbarAttention', value);
      }
    } on MissingPluginException {
      // Unsupported platforms have no taskbar.
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _changes.removeListener(_changed);
    if (!_publishing) {
      unawaited(
        _send(const {'pending': false, 'reduceMotion': true})
            .catchError((Object _) {}),
      );
    }
  }
}
