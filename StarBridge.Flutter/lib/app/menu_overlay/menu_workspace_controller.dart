import 'package:flutter/foundation.dart';

import 'dart:ui';

import 'menu_panel_geometry.dart';

@immutable
class MenuPanelSpec {
  MenuPanelSpec({
    required this.id,
    required this.initialBounds,
    this.minimumSize = const Size(240, 160),
  }) {
    if (id.trim().isEmpty ||
        id.length > 128 ||
        !MenuPanelGeometry.validRect(initialBounds) ||
        !MenuPanelGeometry.validSize(minimumSize)) {
      throw ArgumentError('Invalid menu panel specification.');
    }
  }
  final String id;
  final Rect initialBounds;
  final Size minimumSize;
}

/// Identity of one opened panel; closing/revoking/reopening creates a new lease.
@immutable
class MenuPanelLease {
  const MenuPanelLease._(this.id);
  final String id;
}

@immutable
class MenuLayoutLease {
  const MenuLayoutLease._(this.owner, this.revision);
  final Object owner;
  final int revision;
}

/// Owns layout and panel lifetime only. No business data, disk I/O or timers.
class MenuWorkspaceController extends ChangeNotifier {
  MenuWorkspaceController({
    required Object scope,
    required Iterable<MenuPanelSpec> panels,
    // Public named argument, private mutable storage.
    // ignore: prefer_initializing_formals
  }) : _scope = scope,
       _specs = _index(panels);

  Object _scope;
  final Object _owner = Object();
  Map<String, MenuPanelSpec> _specs;
  final _open = <String, MenuPanelLease>{};
  final _bounds = <String, Rect>{};
  int _revision = 0;
  bool _visible = true;
  bool _disposed = false;
  bool snapWindows = false;

  bool get visible => _visible;
  String? get activeId => _open.isEmpty ? null : _open.keys.last;
  List<MenuPanelLease> get openPanels => List.unmodifiable(_open.values);
  bool allows(String id) => !_disposed && _specs.containsKey(id);
  bool isOpen(String id) => _open.containsKey(id);
  bool isCurrent(MenuPanelLease lease) =>
      !_disposed && identical(_open[lease.id], lease);
  MenuLayoutLease captureLayoutLease() => MenuLayoutLease._(_owner, _revision);

  static Map<String, MenuPanelSpec> _index(Iterable<MenuPanelSpec> panels) {
    final result = <String, MenuPanelSpec>{};
    for (final panel in panels) {
      if (result.containsKey(panel.id) || result.length >= 32) {
        throw ArgumentError('At most 32 unique menu panels may be registered.');
      }
      result[panel.id] = panel;
    }
    return result;
  }

  /// The composition owner supplies a new opaque scope for account/context
  /// changes. Revoked registrations dispose content, not merely disable a tab.
  void reconcile({
    required Object scope,
    required Iterable<MenuPanelSpec> panels,
  }) {
    if (_disposed) return;
    final next = _index(panels);
    if (scope != _scope) {
      _open.clear();
      _bounds.clear();
    }
    _scope = scope;
    _specs = next;
    _open.removeWhere((id, _) => !next.containsKey(id));
    _bounds.removeWhere((id, _) => !next.containsKey(id));
    _changed();
  }

  bool open(String id) {
    if (!allows(id)) return false;
    if (activeId == id) return true;
    _open[id] = _open.remove(id) ?? MenuPanelLease._(id);
    _changed();
    return true;
  }

  void activate(String id) {
    if (_open.containsKey(id)) open(id);
  }

  void close(String id) {
    if (_disposed || _open.remove(id) == null) return;
    _changed();
  }

  void setVisible(bool value, {bool retainPanels = true}) {
    if (_disposed) return;
    if (!value && !retainPanels) _open.clear();
    _visible = value;
    _changed();
  }

  Rect boundsFor(String id, Size viewport) {
    final spec = _specs[id];
    if (spec == null) return Rect.zero;
    return MenuPanelGeometry.fit(
      _bounds[id] ?? spec.initialBounds,
      viewport,
      spec.minimumSize,
    );
  }

  void moveTo(
    MenuPanelLease lease,
    Offset origin,
    Size viewport, {
    bool? snap,
  }) {
    if (!isCurrent(lease) ||
        !_visible ||
        !MenuPanelGeometry.validSize(viewport) ||
        !origin.dx.isFinite ||
        !origin.dy.isFinite) {
      return;
    }
    final rect = boundsFor(lease.id, viewport);
    _bounds[lease.id] = MenuPanelGeometry.move(
      origin & rect.size,
      viewport,
      _specs[lease.id]!.minimumSize,
      _peers(lease.id, viewport),
      (snap ?? snapWindows) ? 12 : 0,
    );
    _changed();
  }

  void resizeTo(MenuPanelLease lease, Size size, Size viewport, {bool? snap}) {
    if (!isCurrent(lease) ||
        !_visible ||
        !MenuPanelGeometry.validSize(viewport) ||
        !size.width.isFinite ||
        !size.height.isFinite) {
      return;
    }
    final rect = boundsFor(lease.id, viewport);
    _bounds[lease.id] = MenuPanelGeometry.resize(
      rect.topLeft & size,
      viewport,
      _specs[lease.id]!.minimumSize,
      _peers(lease.id, viewport),
      (snap ?? snapWindows) ? 12 : 0,
    );
    _changed();
  }

  Iterable<Rect> _peers(String id, Size viewport) => _open.keys
      .where((peer) => peer != id)
      .map((peer) => boundsFor(peer, viewport));

  void recover(String id, Size viewport) {
    if (!allows(id) || !_visible || !MenuPanelGeometry.validSize(viewport)) {
      return;
    }
    _bounds[id] = MenuPanelGeometry.recover(
      boundsFor(id, viewport),
      viewport,
      _specs[id]!.minimumSize,
    );
    open(id);
    _changed();
  }

  void resetPlacements() {
    if (_disposed || !_visible) return;
    _bounds.clear();
    _changed();
  }

  /// Layout-only, versioned data. The existing Host preference owner will decide
  /// where/when to persist it; this never contains scope IDs or business content.
  Map<String, Object?> exportLayout() => {
    'version': 1,
    'panels': [
      for (final spec in _specs.values)
        {
          'id': spec.id,
          'bounds': _encodeRect(_bounds[spec.id] ?? spec.initialBounds),
        },
    ],
    'open': _open.keys.toList(),
  };

  /// Reject late restores after user interaction or scope changes. Reopening is
  /// explicit and constrained to current registrations, never arbitrary IDs.
  bool restoreLayout(
    Object? value, {
    required MenuLayoutLease lease,
    bool reopenPanels = false,
  }) {
    if (_disposed ||
        !identical(lease.owner, _owner) ||
        lease.revision != _revision ||
        value is! Map ||
        value['version'] != 1 ||
        value['panels'] is! List) {
      return false;
    }
    final entries = value['panels'] as List;
    if (entries.length > 32) return false;
    final next = <String, Rect>{};
    for (final entry in entries) {
      if (entry is! Map || entry['id'] is! String) return false;
      final id = entry['id'] as String;
      if (!_specs.containsKey(id)) continue;
      final rect = _decodeRect(entry['bounds']);
      if (rect == null || next.containsKey(id)) return false;
      next[id] = rect;
    }
    final open = value['open'];
    if (open is! List || open.length > 32 || open.any((id) => id is! String)) {
      return false;
    }
    if (open.toSet().length != open.length) return false;
    _bounds
      ..clear()
      ..addAll(next);
    if (reopenPanels) {
      _open.clear();
      for (final id in open.whereType<String>()) {
        if (_specs.containsKey(id)) _open[id] = MenuPanelLease._(id);
      }
    }
    _changed();
    return true;
  }

  static List<double> _encodeRect(Rect r) => [r.left, r.top, r.width, r.height];
  static Rect? _decodeRect(Object? value) {
    if (value is! List || value.length != 4 || value.any((v) => v is! num)) {
      return null;
    }
    final nums = value.cast<num>().map((v) => v.toDouble()).toList();
    final rect = Rect.fromLTWH(nums[0], nums[1], nums[2], nums[3]);
    return MenuPanelGeometry.validRect(rect) ? rect : null;
  }

  void _changed() {
    ++_revision;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _open.clear();
    _bounds.clear();
    super.dispose();
  }
}
