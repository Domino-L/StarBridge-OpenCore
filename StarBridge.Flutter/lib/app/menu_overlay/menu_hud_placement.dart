import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../features/overlay_settings/overlay_workspace_layout_geometry.dart';
import '../../features/overlay_settings/overlay_workspace_layout_item.dart';
import '../localization/app_strings.dart';
import 'menu_bridge_style.dart';
import 'menu_hud_placement_bars.dart';
import 'menu_hud_placement_opacity.dart';
import 'menu_hud_placement_paint.dart';
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
  OverlayWorkspaceLayoutItem? _gestureStart;
  Rect? _eventsStart;
  Offset _gestureDelta = Offset.zero;
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
    }
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

  void _start(String key, Size surface, {required bool resize}) {
    _select(key);
    if (key == 'Crosshair') return;
    final item = _item(key);
    if (item?.isLocked ?? false) {
      _showToast(_t('menu.hudPlace.lockedHint'));
      return;
    }
    _gestureStart = item;
    _eventsStart = key == 'Events' ? _eventsRect(surface) : null;
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

  void _end() {
    _flush();
    setState(() {
      _dragging = null;
      _guides = (vertical: const [], horizontal: const []);
    });
  }

  void _nudge(String key, Offset delta, Size surface) {
    if (key == 'Crosshair') return;
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
      final rects = _rects(surface);
      final view = widget.view;
      final notice = rects['Notice'];
      final toolbarTop = notice != null && notice.top <= 0.5
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
                if (_grid)
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
                for (final entry in rects.entries)
                  _module(entry.key, entry.value, surface),
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
                          onDrag: (details) => setState(() {
                            final box =
                                context.findRenderObject() as RenderBox?;
                            final base =
                                _toolbarOffset ??
                                Offset(
                                  ((box?.size.width ?? surface.width) - 760) /
                                      2,
                                  toolbarTop,
                                );
                            _toolbarOffset = Offset(
                              (base.dx + details.delta.dx).clamp(
                                0,
                                surface.width - 200,
                              ),
                              (base.dy + details.delta.dy).clamp(
                                0,
                                surface.height - 60,
                              ),
                            );
                          }),
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
                        ),
                      ),
                    ),
                  ),
                ),
                if (_toast case final toast?)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 150,
                    child: Center(
                      child: Container(
                        key: const ValueKey('menu-hud-place-toast'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: BridgeInk.window,
                          border: Border(
                            top: BorderSide(
                              color: view.placeResult == 'saved'
                                  ? BridgeInk.green
                                  : BridgeInk.amber,
                            ),
                          ),
                        ),
                        child: Text(
                          toast,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _module(String key, Rect rect, Size surface) {
    final selected = _selected == key, dragging = _dragging == key;
    final hovered = _hovered == key;
    final locked = _item(key)?.isLocked ?? false;
    final resizable = _layoutModules.contains(key) && !locked;
    final tagBelow = rect.top < 30;
    return Positioned.fromRect(
      rect: rect,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = key),
        onExit: (_) =>
            setState(() => _hovered = _hovered == key ? null : _hovered),
        cursor: key == 'Crosshair' || locked
            ? SystemMouseCursors.basic
            : SystemMouseCursors.move,
        child: GestureDetector(
          key: ValueKey('menu-hud-place-module-$key'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _select(key),
          onPanStart: (_) => _start(key, surface, resize: false),
          onPanUpdate: (details) => _update(
            key,
            details.delta,
            details.globalPosition,
            surface,
            resize: false,
          ),
          onPanEnd: (_) => _end(),
          onPanCancel: _end,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: MenuHudModuleOutline(
                    selected: selected,
                    dragging: dragging,
                    hovered: hovered,
                  ),
                ),
              ),
              if (selected || hovered)
                Positioned(
                  left: -1,
                  top: tagBelow ? null : -26,
                  bottom: tagBelow ? -26 : null,
                  child: Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: BridgeInk.placementLabel,
                      border: Border(top: BorderSide(color: BridgeInk.blue)),
                    ),
                    child: Text(
                      [
                        _t('menu.hudQuick.module.$key'),
                        if (locked) _t('menu.hudPlace.locked'),
                        if (key == 'Crosshair') _t('menu.hudPlace.fixed'),
                      ].join(' · '),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              if (resizable)
                Positioned(
                  right: -10,
                  bottom: -10,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeDownRight,
                    child: GestureDetector(
                      key: ValueKey('menu-hud-place-grip-$key'),
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => _start(key, surface, resize: true),
                      onPanUpdate: (details) => _update(
                        key,
                        details.delta,
                        details.globalPosition,
                        surface,
                        resize: true,
                      ),
                      onPanEnd: (_) => _end(),
                      onPanCancel: _end,
                      // A 32 px target; the drawn grip keeps its size and place.
                      child: Semantics(
                        label: _t('menu.hudPlace.resize'),
                        child: const SizedBox.square(
                          dimension: 32,
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: SizedBox.square(
                              dimension: 24,
                              child: CustomPaint(painter: MenuHudGrip()),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _readout(String key, Rect rect, Size surface) {
    final text = switch (key) {
      'Notice' =>
        '${_t(rect.top <= 0.5 ? 'menu.hudPlace.dockTop' : 'menu.hudPlace.dockBottom')} · X ${rect.left.round()} · ${rect.width.round()} × ${rect.height.round()}',
      'Events' =>
        '${_t((_localEvents?.side ?? widget.view.eventSide) == 'Left' ? 'menu.hudPlace.left' : 'menu.hudPlace.right')} · Y ${rect.top.round()}',
      _ =>
        'X ${rect.left.round()} · Y ${rect.top.round()} · ${rect.width.round()} × ${rect.height.round()}',
    };
    final below = rect.bottom + 40 < surface.height;
    return Positioned(
      left: rect.left.clamp(4, surface.width - 320),
      top: below ? rect.bottom + 10 : rect.top - 34,
      child: IgnorePointer(
        child: Container(
          key: const ValueKey('menu-hud-place-readout'),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: BridgeInk.placementReadout,
            border: Border.all(color: menuHudGuide),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }

  Widget _moduleTools(String key, Rect rect, Size surface) {
    final item = _layoutModules.contains(key) ? _item(key) : null;
    // A top-docked notice keeps its tools beside it, clear of the main bar.
    final beside = key == 'Notice' && rect.top <= 0.5;
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
          if (item == null) return;
          _sendItem(
            OverlayWorkspaceLayoutGeometry.resetPosition(
              item,
              widget.view.presetId,
            ),
            first: true,
          );
        },
        onHide: () => _hide(key),
      ),
    );
  }
}
