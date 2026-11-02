import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'starbridge_activation_origin.dart';
import 'starbridge_interaction_theme.dart';
import 'starbridge_native_menu_item.dart';

/// Presentation tree only. Commands and confirmed selection stay with callers.
@immutable
class StarBridgeCascadeEntry {
  const StarBridgeCascadeEntry({
    required this.id,
    required this.label,
    required this.child,
    this.onActivate,
    this.children,
    this.selected,
    this.keepOpen = false,
    this.footer,
    this.before,
  });
  final Object id;
  final String label;
  final Widget child;
  final ValueChanged<InteractionSource>? onActivate;
  final List<StarBridgeCascadeEntry>? children;
  final Widget? footer, before;
  final bool? selected;
  final bool keepOpen;
  bool get enabled =>
      children != null ? children!.isNotEmpty : onActivate != null;
}

/// SDK RawMenuAnchor owns hierarchy, outside-tap groups and overlay visibility.
/// This separate adapter does not reinterpret the existing flat-menu contract.
class StarBridgeCascadingMenu extends StatefulWidget {
  const StarBridgeCascadingMenu({
    required this.entries,
    required this.label,
    required this.builder,
    this.header,
    this.footer,
    this.onOpen,
    this.onClose,
    this.maximumSize = const Size(340, 520),
    this.anchorFocus,
    this.submenu = false,
    this.closeRoot,
    super.key,
  });
  final List<StarBridgeCascadeEntry> entries;
  final String label;
  final Widget? header, footer;
  final VoidCallback? onOpen, onClose;
  final Size maximumSize;
  final FocusNode? anchorFocus;
  final bool submenu;
  final ValueChanged<InteractionSource>? closeRoot;
  final Widget Function(
    BuildContext,
    MenuController,
    FocusNode,
    ValueChanged<InteractionSource>,
  )
  builder;
  @override
  State<StarBridgeCascadingMenu> createState() => _CascadeState();
}

class _CascadeState extends State<StarBridgeCascadingMenu>
    with SingleTickerProviderStateMixin {
  final _controller = MenuController();
  final _ownedAnchor = FocusNode(debugLabel: 'cascade-anchor');
  FocusNode get _anchor => widget.anchorFocus ?? _ownedAnchor;
  final _rows = <Object, FocusNode>{};
  late final _animation = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.dismissed) _finish();
    });
  InteractionSource _source = InteractionSource.pointer;
  InteractionSource _openingSource = InteractionSource.programmatic;
  VoidCallback? _hide;
  bool _closing = false;
  int _generation = 0;
  List<StarBridgeCascadeEntry>? _exit;
  Widget? _exitHeader, _exitFooter;
  List<StarBridgeCascadeEntry> get _display => _exit ?? widget.entries;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    final currentIds = widget.entries.map((e) => e.id).toSet();
    assert(
      currentIds.length == widget.entries.length,
      'Menu ids must be unique per level',
    );
    final ids = {...currentIds, ...?_exit?.map((e) => e.id)};
    var repair = false;
    for (final id in _rows.keys.toList()) {
      if (!ids.contains(id)) {
        final old = _rows.remove(id)!;
        repair |= old.hasFocus;
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    }
    for (final e in widget.entries) {
      final node = _rows.putIfAbsent(
        e.id,
        () => FocusNode(debugLabel: 'cascade-${e.id}'),
      );
      repair |= node.hasFocus && !e.enabled;
      node.canRequestFocus = e.enabled;
    }
    if (repair) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.isOpen && !_closing) _first();
      });
    }
  }

  @override
  void didUpdateWidget(StarBridgeCascadingMenu old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data = resolveStarBridgeInteraction(context);
    final duration = surfaceDurations(data, SurfaceKind.menu);
    _animation
      ..duration = duration.enter
      ..reverseDuration = duration.exit;
    if (!data.animates && _animation.isAnimating) {
      _animation.value = _closing ? 0 : 1;
    }
  }

  void _toggle(InteractionSource source) {
    if (!mounted) return;
    _source = source;
    if (_controller.isOpen && !_closing) {
      _controller.close();
    } else {
      _controller.open();
    }
  }

  void _open(Offset? position, VoidCallback show) {
    if (!mounted) return;
    _openingSource = _source;
    _generation++;
    _closing = false;
    _hide = null;
    _exit = null;
    _exitHeader = null;
    _exitFooter = null;
    if (!_controller.isOpen) show();
    if (_source == InteractionSource.keyboard ||
        !resolveStarBridgeInteraction(context).animates) {
      _animation.value = 1;
    } else {
      _animation.forward();
    }
    if (_source == InteractionSource.keyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.isOpen && !_closing) _first();
      });
    }
    _source = InteractionSource.pointer;
    setState(() {});
  }

  void _close(InteractionSource source) {
    if (mounted) {
      _source = source;
      _controller.close();
    }
  }

  void _closeRequested(VoidCallback hide) {
    if (!mounted || !_controller.isOpen) return;
    _generation++;
    _hide = hide;
    _closing = true;
    _exit ??= List.unmodifiable(widget.entries);
    _exitHeader = widget.header;
    _exitFooter = widget.footer;
    _anchor.requestFocus();
    final instant =
        _source == InteractionSource.keyboard ||
        !resolveStarBridgeInteraction(context).animates;
    _source = InteractionSource.pointer;
    setState(() {});
    if (instant || _animation.value == 0) {
      _animation.value = 0;
      _finish();
    } else {
      _animation.reverse();
    }
  }

  void _finish() {
    final hide = _hide, generation = _generation;
    if (hide == null) return;
    void complete() {
      if (!mounted || _generation != generation || _hide != hide) return;
      _hide = null;
      hide();
      _closing = false;
      _exit = null;
      _exitHeader = null;
      _exitFooter = null;
      _sync();
      if (mounted) setState(() {});
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => complete());
    } else {
      complete();
    }
  }

  void _focus(Object id) {
    final node = _rows[id];
    node?.requestFocus();
    if (node?.context case final context?) {
      Scrollable.ensureVisible(context, duration: Duration.zero);
    }
  }

  void _first() {
    final enabled = widget.entries.where((e) => e.enabled);
    if (enabled.isEmpty) {
      _anchor.requestFocus();
    } else {
      _focus(enabled.first.id);
    }
  }

  void _move(int direction, {bool edge = false}) {
    if (_closing) return;
    final list = widget.entries.where((e) => e.enabled).toList();
    if (list.isEmpty) return;
    final current = list.indexWhere((e) => _rows[e.id]!.hasFocus);
    final index = edge || current < 0
        ? (direction > 0 ? 0 : list.length - 1)
        : (current + direction) % list.length;
    _focus(list[index].id);
  }

  void _activate(Object id, InteractionSource source) {
    if (!mounted || _closing) return;
    final current = widget.entries.where((e) => e.id == id && e.enabled);
    if (current.isEmpty) return;
    final e = current.single;
    if (e.onActivate == null) return;
    if (!e.keepOpen) (widget.closeRoot ?? _close)(source);
    runStarBridgeSynchronousActivation(source, () => e.onActivate!(source));
  }

  @override
  void dispose() {
    _generation++;
    _hide = null;
    _animation.dispose();
    _ownedAnchor.dispose();
    for (final node in _rows.values) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _button(
    StarBridgeCascadeEntry e,
    InteractionData data,
    FocusNode node,
    ValueChanged<InteractionSource>? action,
  ) {
    if (data.suite != InteractionSuite.standard) {
      return SuitePressable(
        key: e.id is String ? Key(e.id as String) : ValueKey(e.id),
        kind: PressableKind.menuItem,
        focusNode: node,
        semanticLabel: e.label,
        semanticSelected: e.selected,
        minHeight: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        onActivate: action,
        child: ExcludeSemantics(child: e.child),
      );
    }
    return StarBridgeNativeMenuItem(
      key: ValueKey(('native-menu-item', e.id)),
      controlKey: e.id is String ? Key(e.id as String) : ValueKey(e.id),
      focusNode: node,
      animated: !data.reduceMotion,
      selected: e.selected,
      label: e.label,
      onActivate: action,
      child: e.child,
    );
  }

  Widget _row(StarBridgeCascadeEntry e, InteractionData data) {
    final node = _rows[e.id];
    if (node == null) return const SizedBox.shrink();
    if (e.children case final children?) {
      return StarBridgeCascadingMenu(
        key: ValueKey(('branch', e.id)),
        entries: children,
        label: e.label,
        anchorFocus: node,
        submenu: true,
        footer: e.footer,
        maximumSize: Size(
          widget.maximumSize.width.clamp(0, 224),
          widget.maximumSize.height,
        ),
        closeRoot: widget.closeRoot ?? _close,
        builder: (context, controller, focus, toggle) =>
            _button(e, data, focus, e.enabled ? toggle : null),
      );
    }
    final row = _button(
      e,
      data,
      node,
      e.enabled ? (source) => _activate(e.id, source) : null,
    );
    return e.enabled
        ? MouseRegion(onHover: (_) => node.requestFocus(), child: row)
        : IgnorePointer(child: ExcludeFocus(child: row));
  }

  @override
  Widget build(BuildContext context) => StarBridgeInteractionRegion(
    child: Builder(
      builder: (context) => RawMenuAnchor(
        controller: _controller,
        childFocusNode: _anchor,
        consumeOutsideTaps: false,
        onOpen: widget.onOpen,
        onClose: widget.onClose,
        onOpenRequested: _open,
        onCloseRequested: _closeRequested,
        builder: (context, controller, _) => CallbackShortcuts(
          bindings: {
            for (final key in [
              LogicalKeyboardKey.enter,
              LogicalKeyboardKey.space,
              LogicalKeyboardKey.numpadEnter,
            ])
              SingleActivator(key): () => _toggle(InteractionSource.keyboard),
            if (controller.isOpen || widget.submenu)
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  (widget.closeRoot ?? _close)(InteractionSource.keyboard),
            if (!widget.submenu)
              const SingleActivator(LogicalKeyboardKey.arrowDown): () {
                if (!controller.isOpen) _toggle(InteractionSource.keyboard);
                _move(1);
              },
            if (widget.submenu)
              const SingleActivator(LogicalKeyboardKey.arrowRight): () {
                if (!controller.isOpen) _toggle(InteractionSource.keyboard);
              },
            if (widget.submenu)
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                  _close(InteractionSource.keyboard),
          },
          child: Semantics(
            button: true,
            enabled: widget.entries.isNotEmpty,
            label: widget.label,
            expanded: controller.isOpen,
            excludeSemantics: true,
            onTap: widget.entries.isEmpty
                ? null
                : () => _toggle(InteractionSource.keyboard),
            child: widget.builder(context, controller, _anchor, _toggle),
          ),
        ),
        overlayBuilder: (context, info) {
          final data = resolveStarBridgeInteraction(context);
          return starBridgeInitialReadViewport(
            context,
            source: _openingSource,
            child: Positioned.fill(
              child: CustomSingleChildLayout(
                delegate: _CascadeLayout(
                  info.anchorRect,
                  widget.submenu,
                  widget.maximumSize,
                ),
                child: TapRegion(
                  groupId: info.tapRegionGroupId,
                  onTapOutside: (_) => _close(InteractionSource.pointer),
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape): () =>
                          (widget.closeRoot ?? _close)(
                            InteractionSource.keyboard,
                          ),
                      const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                          _close(InteractionSource.keyboard),
                      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                          _move(1),
                      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                          _move(-1),
                      const SingleActivator(LogicalKeyboardKey.home): () =>
                          _move(1, edge: true),
                      const SingleActivator(LogicalKeyboardKey.end): () =>
                          _move(-1, edge: true),
                    },
                    child: IgnorePointer(
                      ignoring: _closing,
                      child: ExcludeSemantics(
                        excluding: _closing,
                        child: ExcludeFocus(
                          excluding: _closing,
                          child: SuiteSurfaceTransition(
                            animation: _animation,
                            kind: SurfaceKind.menu,
                            child: Material(
                              animationDuration: data.animates
                                  ? kThemeChangeDuration
                                  : Duration.zero,
                              color: data.palette.raised,
                              elevation: 8,
                              shape: RoundedRectangleBorder(
                                borderRadius: suiteRadius(data.suite, 6),
                                side: BorderSide(color: data.palette.border),
                              ),
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.all(4),
                                child: SizedBox(
                                  width: widget.maximumSize.width,
                                  child: FocusTraversalGroup(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        ?(_closing
                                            ? _exitHeader
                                            : widget.header),
                                        for (final e in _display) ...[
                                          ?e.before,
                                          _row(e, data),
                                        ],
                                        ?(_closing
                                            ? _exitFooter
                                            : widget.footer),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _CascadeLayout extends SingleChildLayoutDelegate {
  _CascadeLayout(this.anchor, this.submenu, this.maximum);
  final Rect anchor;
  final bool submenu;
  final Size maximum;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: (constraints.maxWidth - 16).clamp(0, maximum.width),
        maxHeight: (constraints.maxHeight - 16).clamp(0, maximum.height),
      );
  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = submenu ? anchor.right + 4 : anchor.left;
    var y = submenu ? anchor.top : anchor.bottom + 6;
    if (x + child.width > size.width - 8 && submenu) {
      x = anchor.left - child.width - 4;
    }
    if (y + child.height > size.height - 8 && !submenu) {
      y = anchor.top - child.height - 6;
    }
    return Offset(
      x.clamp(8, (size.width - child.width - 8).clamp(8, double.infinity)),
      y.clamp(8, (size.height - child.height - 8).clamp(8, double.infinity)),
    );
  }

  @override
  bool shouldRelayout(_CascadeLayout old) =>
      old.anchor != anchor || old.submenu != submenu || old.maximum != maximum;
}
