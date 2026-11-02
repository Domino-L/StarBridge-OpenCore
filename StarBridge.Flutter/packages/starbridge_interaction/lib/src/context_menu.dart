import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'menu_button.dart';
import 'pressable.dart';
import 'suite.dart';
import 'surface_transition.dart';

/// Opens a context menu at [position] (global). The menu flips to stay
/// inside the window and grows from the corner nearest the pointer. Rows
/// with [SuiteMenuAction.children] open a submenu on hover (after a short
/// intent delay), click, or →; ← / Esc close the submenu first, then the
/// menu. Outside taps close everything and still reach their target.
///
/// [source] = keyboard (Shift+F10, the Menu key) opens it at once with focus
/// on the first row. Completes when the menu closes.
Future<void> showSuiteContextMenu(
  BuildContext context, {
  required Offset position,
  required List<SuiteMenuAction> actions,
  InteractionSource source = InteractionSource.pointer,
}) {
  final overlay = Overlay.of(context);
  final done = Completer<void>();
  late OverlayEntry entry;
  var themes = InheritedTheme.capture(from: context, to: overlay.context);
  final link = InteractionScope.linkOf(context);
  final data = InteractionScope.of(context);
  entry = OverlayEntry(
    // The entry lives in the overlay, outside the caller's subtree: follow
    // the caller's interaction scope live, and re-capture its themes on
    // every rebuild (an app theme change rebuilds this entry) so an open
    // menu never keeps a stale look.
    builder: (ctx) {
      Theme.of(ctx);
      if (context.mounted) {
        themes = InheritedTheme.capture(from: context, to: overlay.context);
      }
      final menu = Material(
          type: MaterialType.transparency,
          child: _ContextLayer(
            position: position,
            actions: actions,
            keyboard: source == InteractionSource.keyboard,
            onClosed: () {
              entry.remove();
              entry.dispose();
              if (!done.isCompleted) done.complete();
            },
          ),
        );
      return themes.wrap(
        link != null
            ? InteractionScope.follow(link, child: menu)
            : InteractionScope(data: data, child: menu),
      );
    },
  );
  overlay.insert(entry);
  return done.future;
}

class _ContextLayer extends StatefulWidget {
  const _ContextLayer({
    required this.position,
    required this.actions,
    required this.keyboard,
    required this.onClosed,
  });

  final Offset position;
  final List<SuiteMenuAction> actions;
  final bool keyboard;
  final VoidCallback onClosed;

  @override
  State<_ContextLayer> createState() => _ContextLayerState();
}

class _ContextLayerState extends State<_ContextLayer>
    with TickerProviderStateMixin {
  late final _main = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.dismissed) widget.onClosed();
    });
  late final _sub = AnimationController(vsync: this);
  final _region = Object();
  final _mainRows = <FocusNode>[];
  final _subRows = <FocusNode>[];
  int? _subIndex;
  Timer? _intent;
  final _rowKeys = <GlobalKey>[];
  static const _width = 196.0;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < widget.actions.length; i++) {
      _mainRows.add(FocusNode(debugLabel: 'ctx-$i'));
      _rowKeys.add(GlobalKey());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final data = InteractionScope.of(context);
      final d = surfaceDurations(data, SurfaceKind.menu);
      _main
        ..duration = d.enter
        ..reverseDuration = d.exit;
      if (widget.keyboard || !data.animates) {
        _main.value = 1;
        _focusFirst(_mainRows, widget.actions);
      } else {
        _main.forward();
      }
    });
  }

  /// Reduced motion turned on mid-transition: settle both layers now
  /// (closing → closed, opening → open). Deferred past the build because
  /// closing removes the overlay entry.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (InteractionScope.of(context).animates) return;
    if (!_main.isAnimating && !_sub.isAnimating) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_sub.isAnimating) _sub.value = 1;
      if (_main.isAnimating) {
        _main.value = _main.status == AnimationStatus.reverse ? 0 : 1;
      }
    });
  }

  @override
  void dispose() {
    _intent?.cancel();
    _main.dispose();
    _sub.dispose();
    for (final f in [..._mainRows, ..._subRows]) {
      f.dispose();
    }
    super.dispose();
  }

  void _focusFirst(List<FocusNode> nodes, List<SuiteMenuAction> actions) {
    for (var i = 0; i < actions.length; i++) {
      if (actions[i].enabled) {
        nodes[i].requestFocus();
        return;
      }
    }
  }

  void _close({bool instant = false}) {
    _intent?.cancel();
    final data = InteractionScope.of(context);
    if (instant || !data.animates) {
      widget.onClosed();
    } else {
      _main.reverse();
    }
  }

  void _openSub(int i, {bool keyboard = false}) {
    _intent?.cancel();
    final children = widget.actions[i].children;
    if (children == null || children.isEmpty) return;
    if (_subIndex == i) {
      if (keyboard) _focusFirst(_subRows, children);
      return;
    }
    for (final f in _subRows) {
      f.dispose();
    }
    _subRows
      ..clear()
      ..addAll([
        for (var j = 0; j < children.length; j++)
          FocusNode(debugLabel: 'ctx-sub-$j'),
      ]);
    setState(() => _subIndex = i);
    final data = InteractionScope.of(context);
    if (keyboard || !data.animates) {
      _sub.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusFirst(_subRows, children);
      });
    } else {
      _sub
        ..duration = surfaceDurations(data, SurfaceKind.menu).enter
        ..forward(from: 0);
    }
  }

  void _closeSub({bool refocus = true}) {
    final i = _subIndex;
    if (i == null) return;
    setState(() => _subIndex = null);
    _sub.value = 0;
    if (refocus) _mainRows[i].requestFocus();
  }

  void _move(int dir) {
    final inSub = _subRows.any((f) => f.hasFocus);
    final nodes = inSub ? _subRows : _mainRows;
    final actions = inSub
        ? widget.actions[_subIndex!].children!
        : widget.actions;
    var i = nodes.indexWhere((f) => f.hasFocus);
    for (var n = 0; n < actions.length; n++) {
      i = (i + dir) % actions.length;
      if (i < 0) i += actions.length;
      if (actions[i].enabled) {
        nodes[i].requestFocus();
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final size = MediaQuery.sizeOf(context);
    final rowH = 32.0;
    final menuH =
        widget.actions.length * rowH +
        8 +
        widget.actions.where((a) => a.dividerBefore).length * 7;
    final flipX = widget.position.dx + _width > size.width - 8;
    final flipY = widget.position.dy + menuH > size.height - 8;
    final left = flipX ? widget.position.dx - _width : widget.position.dx;
    final top = flipY ? widget.position.dy - menuH : widget.position.dy;
    final origin = Alignment(flipX ? 1 : -1, flipY ? 1 : -1);

    Widget? sub;
    final si = _subIndex;
    if (si != null) {
      final children = widget.actions[si].children!;
      final rowBox =
          _rowKeys[si].currentContext?.findRenderObject() as RenderBox?;
      final rowTop = rowBox == null
          ? top
          : rowBox.localToGlobal(Offset.zero).dy - 4;
      final subFlip = left + _width * 2 > size.width - 8;
      sub = Positioned(
        left: subFlip ? left - _width + 4 : left + _width - 4,
        top: rowTop.clamp(8.0, size.height - children.length * rowH - 16),
        // TapRegion goes inside: Positioned must be the Stack's direct child.
        child: TapRegion(
          groupId: _region,
          child: SuiteSurfaceTransition(
            animation: _sub,
            kind: SurfaceKind.menu,
            alignment: Alignment(subFlip ? 1 : -1, -1),
            radius: 8,
            child: _panel(data, children, _subRows, sub: true),
          ),
        ),
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _subIndex != null ? _closeSub() : _close(instant: true),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _closeSub(),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          final i = _mainRows.indexWhere((f) => f.hasFocus);
          if (i >= 0) _openSub(i, keyboard: true);
        },
      },
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            child: TapRegion(
              groupId: _region,
              onTapOutside: (_) => _close(),
              child: SuiteSurfaceTransition(
                animation: _main,
                kind: SurfaceKind.menu,
                alignment: origin,
                radius: 8,
                child: _panel(data, widget.actions, _mainRows),
              ),
            ),
          ),
          ?sub,
        ],
      ),
    );
  }

  Widget _panel(
    InteractionData data,
    List<SuiteMenuAction> actions,
    List<FocusNode> nodes, {
    bool sub = false,
  }) {
    final p = data.palette;
    return Container(
      width: _width,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.raised,
        borderRadius: suiteRadius(data.suite, 8),
        border: Border.all(color: p.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: FocusTraversalGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (actions[i].dividerBefore) ...[
                const SizedBox(height: 3),
                Divider(height: 1, color: p.border.withValues(alpha: 0.5)),
                const SizedBox(height: 3),
              ],
              _row(data, actions[i], nodes[i], i, sub),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(
    InteractionData data,
    SuiteMenuAction a,
    FocusNode node,
    int i,
    bool sub,
  ) {
    final p = data.palette;
    final hasChildren = a.children?.isNotEmpty ?? false;
    final open = !sub && _subIndex == i;
    return MouseRegion(
      onEnter: (_) {
        if (sub) return;
        _intent?.cancel();
        if (hasChildren) {
          // Short intent delay so passing over a row does not flash submenus.
          _intent = Timer(const Duration(milliseconds: 180), () {
            if (mounted) _openSub(i);
          });
        } else if (_subIndex != null) {
          _intent = Timer(const Duration(milliseconds: 220), () {
            if (mounted) _closeSub(refocus: false);
          });
        }
      },
      child: KeyedSubtree(
        key: sub ? null : _rowKeys[i],
        child: SuitePressable(
          kind: PressableKind.menuItem,
          focusNode: node,
          selected: open,
          baseRadius: 5,
          minHeight: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          semanticLabel: a.label,
          onActivate: !a.enabled
              ? null
              : (source) {
                  if (hasChildren) {
                    _openSub(i, keyboard: source == InteractionSource.keyboard);
                    return;
                  }
                  _close(instant: source == InteractionSource.keyboard);
                  a.onSelected!();
                },
          builder: (context, v) {
            final color = !a.enabled
                ? p.textDisabled
                : (a.danger ? p.danger : v.foreground);
            return Row(
              spacing: 10,
              children: [
                if (a.icon != null) Icon(a.icon, size: 16, color: color),
                Expanded(
                  child: Text(
                    a.label,
                    style: TextStyle(fontSize: 13, color: color),
                  ),
                ),
                if (hasChildren)
                  Icon(Icons.chevron_right, size: 15, color: color),
              ],
            );
          },
        ),
      ),
    );
  }
}
