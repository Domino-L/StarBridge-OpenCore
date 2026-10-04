import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Count-only presentation. No identities, messages or read authority cross
/// the auxiliary engine boundary.
final class MenuAttention {
  const MenuAttention({
    this.friends = 0,
    this.comms = 0,
    this.rooms = 0,
    this.organizations = 0,
  });
  final int friends, comms, rooms, organizations;
  static const keys = {'friends', 'comms', 'rooms', 'organizations'};
  static const maximum = 1000000000;
  Map<String, int> toMap() => {
    'friends': friends.clamp(0, maximum),
    'comms': comms.clamp(0, maximum),
    'rooms': rooms.clamp(0, maximum),
    'organizations': organizations.clamp(0, maximum),
  };
  int count(String tool) => toMap()[tool] ?? 0;
  static MenuAttention? parse(Object? payload) {
    if (payload is! String || payload.length > 256) return null;
    try {
      final raw = jsonDecode(payload);
      if (raw is! Map ||
          raw.length != keys.length ||
          !setEquals(raw.keys.toSet(), keys) ||
          raw.values.any((v) => v is! int || v < 0 || v > maximum)) {
        return null;
      }
      return MenuAttention(
        friends: raw['friends'] as int,
        comms: raw['comms'] as int,
        rooms: raw['rooms'] as int,
        organizations: raw['organizations'] as int,
      );
    } on Object {
      return null;
    }
  }
}

/// Visible-menu subscription to the primary application's existing counters.
/// Owns no business port, polling, cache or read receipt. Disposal removes only
/// these listeners, never disposes the application-owned sources.
final class MenuAttentionSource extends ChangeNotifier {
  MenuAttentionSource({
    required List<Listenable> changes,
    required this.read,
    required this.isCurrent,
    Stream<void>? invalidations,
  }) : _changes = Listenable.merge(changes) {
    _changes.addListener(_update);
    _invalidations = invalidations?.listen((_) {
      _revoked = true;
      _update();
    });
    _update();
  }
  final Listenable _changes;
  final MenuAttention Function() read;
  final bool Function() isCurrent;
  StreamSubscription<void>? _invalidations;
  bool _revoked = false, _disposed = false;
  MenuAttention _value = const MenuAttention();
  MenuAttention get value => _value;
  void _update() {
    if (_disposed) return;
    final next = !_revoked && isCurrent() ? read() : const MenuAttention();
    if (mapEquals(next.toMap(), _value.toMap())) return;
    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _changes.removeListener(_update);
    unawaited(_invalidations?.cancel());
    super.dispose();
  }
}
