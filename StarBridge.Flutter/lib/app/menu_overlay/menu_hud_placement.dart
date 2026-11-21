import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../features/overlay_settings/overlay_visor_layout.dart';
import '../../features/overlay_settings/overlay_visor_projection.dart';
import '../../features/overlay_settings/overlay_workspace_layout_geometry.dart';
import '../../features/overlay_settings/overlay_workspace_models.dart';
import '../localization/app_strings.dart';
import 'menu_bridge_style.dart';
import 'menu_hud_placement_bars.dart';
import 'menu_hud_placement_module.dart';
import 'menu_hud_placement_opacity.dart';
import 'menu_hud_placement_paint.dart';
import 'menu_hud_placement_samples.dart';
import 'menu_hud_placement_visor.dart';
import 'menu_hud_quick_view.dart';

const _layoutModules = ['Notice', 'Squads', 'Members', 'Chat'];
const _eventSlot =
    OverlayWorkspaceLayoutGeometry.singleEventNotificationPlacementHeight;

/// Arrange mode. The menu window sits directly above the information overlay
/// and shows only this transparent layer: outlines, guides and two toolbars.
/// Every edit goes to the primary workspace draft, whose live runtime sync
/// moves the real overlay underneath. Done saves, Cancel discards, and both
/// return to the game through [onDismiss].
class MenuHudPlacementLayer extends StatefulWidget {
  const MenuHudPlacementLayer({
    super.key,
    required this.view,
    required this.onAction,
    required this.onDismiss,
  });
  final MenuHudQuickView view;
  final void Function(String key, String value) onAction;
  final VoidCallback onDismiss;

  @override
  State<MenuHudPlacementLayer> createState() => _MenuHudPlacementLayerState();
}

class _MenuHudPlacementLayerState extends State<MenuHudPlacementLayer> {
  bool _grid = true, _align = true, _hiddenOpen = false, _opacityOpen = false;
  bool _edited = false, _finishing = false;
  String? _selected, _hovered, _dragging, _toast;
  Offset? _toolbarOffset;
  Timer? _toastTimer, _sendTimer;
  // Local geometry while a gesture is in flight, so outlines track the pointer
  // even before the primary engine echoes the draft back.
  final _local = <String, OverlayWorkspaceLayoutItem>{};
  ({String side, double y})? _localEvents;
  double? _localEventsX; // the visor events' place across (11-12)
  ({double x, double y})? _localBadge;
  OverlayWorkspaceLayoutItem? _gestureStart;
  Rect? _eventsStart, _badgeStart;
  Size _surface = Size.zero;
  Offset _gestureDelta = Offset.zero;
  Offset? _grab;
  bool _gestureFirst = false;
  String? _pendingKey, _pendingValue;
  ({List<double> vertical, List<double> horizontal}) _guides = (
    vertical: const [],
    horizontal: const [],
  );
  final _focus = FocusNode(debugLabel: 'menu-hud-placement');

  String _t(String key, [Map<String, String> args = const {}]) {
    var value = AppStrings.of(context).text(key);
    for (final entry in args.entries) {
      value = value.replaceAll('{${entry.key}}', entry.value);
    }
    return value;
  }

  @override
  void didUpdateWidget(MenuHudPlacementLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final result = widget.view.placeResult;
    if (result != oldWidget.view.placeResult && result.isNotEmpty) {
      _showToast(switch (result) {
        'saved' when _edited => _t('menu.hudPlace.saved', {
          'preset': widget.view.presetName,
        }),
        'saved' => _t('menu.hudPlace.unchanged'),
        _ => _t('menu.hudPlace.cancelled'),
      });
      // Let the confirmation register, then return to the game.
      Timer(const Duration(milliseconds: 700), () {
        if (mounted) widget.onDismiss();
      });
    }
    if (_finishing &&
        result.isEmpty &&
        widget.view.note?.kind == 'failed' &&
        oldWidget.view.note?.kind != 'failed') {
      _finishing = false;
      _showToast(_t('menu.hudPlace.failed'));
    }
    if (_dragging == null) {
      _local.clear();
      _localEvents = null;
      _localEventsX = null;
      _localBadge = null;
    }
  }

  // ---- the visor (11-11 user: "Alt+M 按面罩排布") ----

  /// The visor's settings while placing on it, else null (the older,
  /// free-size placement).
  OverlayWorkspaceSettings? get _visor => widget.view.visor;

  /// The visor settings with the gesture in flight applied (events, badge).
  OverlayWorkspaceSettings? get _visorNow => switch (_visor) {
    final visor? => MenuHudVisorPlacement.withLocal(
      visor,
      events: _localEvents,
      eventsX: _localEventsX,
      badge: _localBadge,
    ),
    null => null,
  };

  /// Sends one visor placement step (the first of a gesture at once, so it
  /// starts its own undo step) and shows it before the engine echoes it.
  void _apply(MenuHudVisorEdit? edit) {
    switch (edit) {
      case MenuHudVisorItem(:final item):
        _local[item.key] = item;
        _sendItem(item, first: _gestureFirst);
      case MenuHudVisorEvents(:final right, :final y, :final x):
        final side = right ? 'Right' : 'Left';
        _localEvents = (side: side, y: y);
        _localEventsX = x;
        _send(
          'placeEvents',
          jsonEncode({'side': side, 'y': y, 'x': x, 'first': _gestureFirst}),
          now: _gestureFirst,
        );
      case MenuHudVisorBadge(:final x, :final y):
        _localBadge = (x: x, y: y);
        _send(
          'placeBadge',
          jsonEncode({'x': x, 'y': y, 'first': _gestureFirst}),
          now: _gestureFirst,
        );
      case null:
        return;
    }
    _gestureFirst = false;
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _flush();
    _focus.dispose();
    super.dispose();
  }

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  // ---- outbound intents (throttled to one frame while dragging) ----

  void _send(String key, String value, {bool now = false}) {
    _edited = true;
    if (_pendingKey != null && _pendingKey != key) _flush();
    _pendingKey = key;
    _pendingValue = value;
    if (now) {
      _flush();
      return;
    }
    _sendTimer ??= Timer(const Duration(milliseconds: 16), _flush);
  }

  void _flush() {
    _sendTimer?.cancel();
    _sendTimer = null;
    final key = _pendingKey, value = _pendingValue;
    _pendingKey = _pendingValue = null;
    if (key != null && value != null) widget.onAction(key, value);
  }

  void _sendItem(OverlayWorkspaceLayoutItem item, {required bool first}) =>
      _send(
        'placeItem',
        jsonEncode({'item': item.toMap(), 'first': first}),
        now: first,
      );

  // ---- geometry ----

  bool _visible(String key) => widget.view.modules[key] ?? false;

  List<OverlayWorkspaceLayoutItem> get _items => [
    for (final item in widget.view.layout) _local[item.key] ?? item,
  ];

  OverlayWorkspaceLayoutItem? _item(String key) =>
      _items.where((item) => item.key == key).firstOrNull;

  Map<String, Rect> _rects(Size surface) {
    if (_visorNow case final visor?) {
      return MenuHudVisorPlacement.rects(
        _items,
        visor,
        _visible,
        surface,
        rally: _rallyDrag,
      );
    }
    final shown = [
      for (final item in _items)
        if (_layoutModules.contains(item.key) && _visible(item.key)) item,
    ];
    final rects = OverlayWorkspaceLayoutGeometry.resolveItems(
      shown,
      surfaceSize: surface,
    );
    if (_visible('Events')) rects['Events'] = _eventsRect(surface);
    if (_visible('Crosshair')) {
      rects['Crosshair'] = Rect.fromCenter(
        center: surface.center(Offset.zero),
        width: 80,
        height: 80,
      );
    }
    return rects;
  }

  Rect _eventsRect(Size surface) {
    final events =
        _localEvents ?? (side: widget.view.eventSide, y: widget.view.eventY);
    return OverlayWorkspaceLayoutGeometry.resolveEventNotificationRect(
      surfaceWidth: surface.width,
      surfaceHeight: surface.height,
      side: events.side,
      normalizedY: events.y,
      preferredHeight: _eventSlot * 2,
    );
  }

  // ---- gestures ----

  void _select(String? key) => setState(() {
    _selected = key;
    _opacityOpen = false;
    _hiddenOpen = false;
  });

  void _start(String key, Size surface, {required bool resize, Offset? at}) {
    _select(key);
    final box = context.findRenderObject() as RenderBox?;
    _grab = at == null ? null : box?.globalToLocal(at);
    if (key == 'Crosshair') return;
    final item = _item(key);
    if (item?.isLocked ?? false) {
      _showToast(_t('menu.hudPlace.lockedHint'));
      return;
    }
    _gestureStart = item;
    final visorRects = _visorNow == null
        ? const <String, Rect>{}
        : _rects(surface);
    _eventsStart = key == 'Events'
        ? (visorRects['Events'] ?? _eventsRect(surface))
        : null;
    _badgeStart = key == 'Badge' ? visorRects['Badge'] : null;
    _gestureDelta = Offset.zero;
    _gestureFirst = true;
    setState(() => _dragging = key);
  }

  void _update(
    String key,
    Offset delta,
    Offset pointer,
    Size surface, {
    required bool resize,
  }) {
    if (_dragging != key) return;
    _gestureDelta += delta;
    if (_visorNow case final visor?) {
      final (edit, guides) = MenuHudVisorPlacement.drag(
        key: key,
        start: _gestureStart,
        startBox: key == 'Events' ? _eventsStart : _badgeStart,
        delta: _gestureDelta,
        pointer: pointer,
        items: _items,
        visor: visor,
        surface: surface,
        snapping: _align,
        grab: _grab,
      );
      _apply(edit);
      setState(
        () => _guides = (
          vertical: [
            for (final guide in guides)
              if (guide.vertical) guide.at,
          ],
          horizontal: [
            for (final guide in guides)
              if (!guide.vertical) guide.at,
          ],
        ),
      );
      return;
    }
    final rects = _rects(surface);
    if (key == 'Events') {
      final start = _eventsStart!;
      final available = (surface.height - start.height).clamp(
        1.0,
        double.infinity,
      );
      var top = (start.top + _gestureDelta.dy).clamp(0.0, available);
      if (_align) {
        for (final target in [0.0, available / 2, available]) {
          if ((top - target).abs() <=
              OverlayWorkspaceLayoutGeometry.edgeSnapThreshold) {
            top = target;
          }
        }
      }
      if (_grid && top != 0 && top != available) {
        top = (top / 16).round() * 16.0;
      }
      final side = pointer.dx < surface.width / 2 ? 'Left' : 'Right';
      _localEvents = (side: side, y: top / available);
      _send(
        'placeEvents',
        jsonEncode({
          'side': side,
          'y': top / available,
          'first': _gestureFirst,
        }),
        now: _gestureFirst,
      );
      _gestureFirst = false;
      final rect = _eventsRect(surface);
      setState(
        () => _guides = (
          vertical: [surface.width / 2],
          horizontal: menuHudAlignment(rect, const [], surface).horizontal,
        ),
      );
      return;
    }
    final start = _gestureStart;
    if (start == null) return;
    final layout = _items;
    final next = resize
        ? OverlayWorkspaceLayoutGeometry.resize(
            item: start,
            layout: layout,
            delta: _gestureDelta,
            snapPixels: _grid ? 16 : 0,
            smartSnap: _align,
            surfaceSize: surface,
          )
        : OverlayWorkspaceLayoutGeometry.move(
            item: start,
            layout: layout,
            delta: _gestureDelta,
            snapPixels: _grid ? 16 : 0,
            smartSnap: _align,
            surfaceSize: surface,
          );
    _local[key] = next;
    _sendItem(next, first: _gestureFirst);
    _gestureFirst = false;
    final moved = OverlayWorkspaceLayoutGeometry.resolve(
      next,
      surfaceSize: surface,
    );
    setState(() {
      _guides = menuHudAlignment(moved, [
        for (final entry in rects.entries)
          if (entry.key != key && entry.key != 'Crosshair') entry.value,
      ], surface);
    });
  }

  (OverlayWorkspaceLayoutItem, double)? get _rallyDrag =>
      _dragging == 'Notice' && _gestureStart != null
      ? (_gestureStart!, _gestureDelta.dy)
      : null;
  void _end() {
    final key = _dragging;
    if ((_visorNow, _rallyDrag) case (final visor?, (final s, final dy))) {
      _apply(MenuHudVisorPlacement.rallyDrop(s, visor, _surface, dy));
    }
    if (_visorNow case final visor? when key == 'Members' || key == 'Chat') {
      final item = _item(key!);
      if (item != null) {
        final dropped = OverlayVisorLayout.drop(item, _items, visor, _surface);
        if (dropped != null) {
          _local[key] = dropped;
          _sendItem(dropped, first: false);
        }
      }
    }
    _flush();
    setState(() {
      _dragging = null;
      _guides = (vertical: const [], horizontal: const []);
    });
  }

  void _nudge(String key, Offset delta, Size surface) {
    if (key == 'Crosshair') return;
    if (_visorNow case final visor?) {
      _gestureFirst = true;
      _apply(
        MenuHudVisorPlacement.nudge(
          key: key,
          rects: _rects(surface),
          delta: delta,
          items: _items,
          visor: visor,
          surface: surface,
        ),
      );
      return;
    }
    if (key == 'Events') {
      final rect = _eventsRect(surface);
      final available = (surface.height - rect.height).clamp(
        1.0,
        double.infinity,
      );
      final y = ((rect.top + delta.dy).clamp(0.0, available)) / available;
      _send(
        'placeEvents',
        jsonEncode({'side': widget.view.eventSide, 'y': y, 'first': true}),
        now: true,
      );
      return;
    }
    final item = _item(key);
    if (item == null || item.isLocked) return;
    var next = item;
    if (delta.dx != 0) {
      next = OverlayWorkspaceLayoutGeometry.nudge(
        next,
        'x',
        delta.dx,
        surfaceSize: surface,
      );
    }
    if (delta.dy != 0 && key != 'Notice') {
      next = OverlayWorkspaceLayoutGeometry.nudge(
        next,
        'y',
        delta.dy,
        surfaceSize: surface,
      );
    }
    _sendItem(next, first: true);
  }

  void _hide(String key) {
    _send('placeHide', key, now: true);
    _select(null);
  }

  void _done() {
    if (_finishing) return;
    _flush();
    setState(() => _finishing = true);
    widget.onAction('placeDone', '');
  }

  void _cancel() {
    if (_finishing) return;
    _flush();
    setState(() => _finishing = true);
    widget.onAction('placeCancel', '');
  }

  KeyEventResult _key(KeyEvent event, Size surface) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final control = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (key == LogicalKeyboardKey.escape) {
      if (_opacityOpen || _hiddenOpen) {
        setState(() => _opacityOpen = _hiddenOpen = false);
      } else {
        _cancel();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _done();
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.keyZ) {
      _flush();
      widget.onAction(keyboard.isShiftPressed ? 'placeRedo' : 'placeUndo', '');
      return KeyEventResult.handled;
    }
    if (control && key == LogicalKeyboardKey.keyY) {
      _flush();
      widget.onAction('placeRedo', '');
      return KeyEventResult.handled;
    }
    final selected = _selected;
    if (selected == null) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.delete) {
      if (selected == 'Badge') return KeyEventResult.handled;
      _hide(selected);
      return KeyEventResult.handled;
    }
    final step = keyboard.isShiftPressed ? 10.0 : 1.0;
    final delta = switch (key) {
      LogicalKeyboardKey.arrowLeft => Offset(-step, 0),
      LogicalKeyboardKey.arrowRight => Offset(step, 0),
      LogicalKeyboardKey.arrowUp => Offset(0, -step),
      LogicalKeyboardKey.arrowDown => Offset(0, step),
      _ => null,
    };
    if (delta == null) return KeyEventResult.ignored;
    _nudge(selected, delta, surface);
    return KeyEventResult.handled;
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final surface = constraints.biggest;
      _surface = surface;
      final rects = _rects(surface);
      final tilts = switch (_visorNow) {
        final visor? => OverlayVisorProjection.tilts(_items, visor, surface),
        null => const <String, bool>{},
      };
      final view = widget.view;
      final notice = rects['Notice'];
      // a notice in the top half (the visor's rally too) keeps the bar below
      final toolbarTop = notice != null && notice.center.dy < surface.height / 2
          ? notice.bottom + 44
          : 24.0;
      final hidden = {
        for (final key in menuHudQuickModules)
          if (view.modules[key] == false) key: _t('menu.hudQuick.module.$key'),
      };
      final busy = _finishing || view.placeResult.isNotEmpty;
      final faded = _dragging != null;
      return Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (_, event) => _key(event, surface),
        child: Material(
          type: MaterialType.transparency,
          child: DefaultTextStyle(
            style: const TextStyle(
              fontFamily: 'Source Sans 3',
              fontFamilyFallback: ['Source Han Sans CN'],
              color: BridgeInk.text,
              fontSize: 14,
              height: 1.4,
            ),
            child: Stack(
              key: const ValueKey('menu-hud-placement'),
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => _select(null),
                  ),
                ),
                if (_grid && _visor == null)
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: MenuHudPlacementGrid()),
                    ),
                  ),
                const Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: MenuHudPlacementFrame()),
                  ),
                ),
                ?menuHudVisorAids(
                  items: _items,
                  visor: _visorNow,
                  rally: notice,
                  selected: _selected == 'Notice',
                  dragDy: _rallyDrag?.$2,
                  surface: surface,
                ),
                for (final entry in rects.entries)
                  _module(entry.key, entry.value, surface, tilts),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: MenuHudGuides(
                        _guides.vertical,
                        _guides.horizontal,
                      ),
                    ),
                  ),
                ),
                if (_dragging case final key? when rects[key] != null)
                  _readout(key, rects[key]!, surface),
                if (_selected case final key?
                    when rects[key] != null && _dragging == null)
                  _moduleTools(key, rects[key]!, surface),
                Positioned(
                  left: _toolbarOffset?.dx ?? 0,
                  right: _toolbarOffset == null ? 0 : null,
                  top: _toolbarOffset?.dy ?? toolbarTop,
                  child: IgnorePointer(
                    ignoring: faded,
                    child: MenuHudPlacementToolbarOpacity(
                      opacity: faded ? .18 : 1,
                      reduceMotion: resolveStarBridgeInteraction(context)
                          .reduceMotion,
                      child: Align(
                        alignment: Alignment.topCenter,
                        widthFactor: _toolbarOffset == null ? null : 1,
                        child: MenuHudPlacementToolbar(
                          text: _t,
                          presetName: view.presetName,
                          changed: view.canUndo,
                          grid: _grid,
                          align: _align,
                          canUndo: view.canUndo,
                          canRedo: view.canRedo,
                          hidden: hidden,
                          hiddenOpen: _hiddenOpen,
                          busy: busy,
                          onDrag: (details) => setState(
                            () => _toolbarOffset = menuHudToolbarOffset(
                              _toolbarOffset,
                              (context.findRenderObject() as RenderBox?)?.size,
                              toolbarTop,
                              details.delta,
                              surface,
                            ),
                          ),
                          onGrid: () => setState(() => _grid = !_grid),
                          onAlign: () => setState(() => _align = !_align),
                          onUndo: () {
                            _flush();
                            widget.onAction('placeUndo', '');
                          },
                          onRedo: () {
                            _flush();
                            widget.onAction('placeRedo', '');
                          },
                          onHiddenOpen: () =>
                              setState(() => _hiddenOpen = !_hiddenOpen),
                          onShow: (key) {
                            _send('placeShow', key, now: true);
                            setState(() {
                              _selected = key;
                              _hiddenOpen = false;
                            });
                          },
                          onCancel: _cancel,
                          onDone: _done,
                          showGrid: _visor == null,
                          hintKey: _visor == null
                              ? 'menu.hudPlace.hint'
                              : 'menu.hudPlace.hintVisor',
                        ),
                      ),
                    ),
                  ),
                ),
                if (_toast case final toast?)
                  MenuHudPlacementToast(
                    text: toast,
                    saved: view.placeResult == 'saved',
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _module(String key, Rect rect, Size surface, Map<String, bool> tilts) {
    final locked = _item(key)?.isLocked ?? false;
    final visor = _visorNow;
    final right = tilts[key];
    final degrees = visor == null ? 0.0 : OverlayVisorProjection.degrees(visor);
    return MenuHudPlacementModule(
      moduleKey: key,
      rect: rect,
      selected: _selected == key,
      dragging: _dragging == key,
      hovered: _hovered == key,
      locked: locked,
      // the visor sizes its blocks itself ("面罩大小"): position only
      resizable: _visor == null && _layoutModules.contains(key) && !locked,
      tag: menuHudModuleTag(_t, key, _item(key), visor: visor != null),
      resizeLabel: _t('menu.hudPlace.resize'),
      // over the real visor: the side blocks lean as it draws them (11-11)
      transform: right == null || degrees == 0
          ? null
          : OverlayVisorProjection.forWidget(
              rect,
              right: right,
              degrees: degrees,
              surface: surface,
              distance: OverlayVisorProjection.distance(visor!),
            ),
      content: menuHudVisorSample(key, visor, rect, surface),
      onHover: (on) => setState(
        () => _hovered = on ? key : (_hovered == key ? null : _hovered),
      ),
      onSelect: () => _select(key),
      onStart: (resize, at) => _start(key, surface, resize: resize, at: at),
      onMove: (delta, pointer, resize) =>
          _update(key, delta, pointer, surface, resize: resize),
      onEnd: _end,
    );
  }

  Widget _readout(String key, Rect rect, Size surface) =>
      MenuHudPlacementReadout(
        moduleKey: key,
        rect: rect,
        surface: surface,
        visor: _visor != null,
        eventsLeft: (_localEvents?.side ?? widget.view.eventSide) == 'Left',
        text: _t,
      );

  Widget _moduleTools(String key, Rect rect, Size surface) {
    final item = _layoutModules.contains(key) ? _item(key) : null;
    // A top-docked notice keeps its tools beside it, clear of the main bar.
    final beside = key == 'Notice' && rect.center.dy < surface.height / 2;
    final above = rect.top > 70;
    return Positioned(
      left: beside
          ? (rect.right + 12).clamp(0, surface.width - 480)
          : rect.left.clamp(8, surface.width - 480),
      top: beside
          ? 6
          : above
          ? rect.top - 62
          : rect.bottom + 34,
      child: MenuHudModuleTools(
        text: _t,
        moduleKey: key,
        item: item,
        opacityOpen: _opacityOpen,
        onLock: () {
          if (item == null) return;
          _sendItem(item.copyWith(isLocked: !item.isLocked), first: true);
        },
        onOpacityOpen: () => setState(() => _opacityOpen = !_opacityOpen),
        onOpacity: (next, first) {
          setState(() => _local[key] = next);
          _sendItem(next, first: first);
        },
        onReset: () {
          _gestureFirst = true;
          // the badge goes back above the game's key hints; the rally to the top
          _apply(switch (item) {
            null when key == 'Badge' => const MenuHudVisorBadge(-1, -1),
            null => null,
            final item => MenuHudVisorItem(
              OverlayVisorLayout.resetPosition(
                item,
                widget.view.presetId,
                _visor,
              ),
            ),
          });
        },
        onHide: () => _hide(key),
        canHide: key != 'Badge',
        canReset: key == 'Badge',
      ),
    );
  }
}
