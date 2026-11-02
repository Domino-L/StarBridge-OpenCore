import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../tokens/starbridge_tokens.dart';
import 'starbridge_interaction_theme.dart';

/// A flat action menu row. Identity survives insertion/reordering; the caller
/// owns enabled/selected values and the business result, including failures.
@immutable
class StarBridgeMenuEntry {
  const StarBridgeMenuEntry({
    required this.id,
    required this.label,
    required this.child,
    this.onActivate,
    this.selected,
    this.controlKey,
  });
  final Object id;
  final String label;
  final Widget child;
  final ValueChanged<InteractionSource>? onActivate;
  final bool? selected;

  /// Optional original render identity; the stable action/focus id stays [id].
  final Key? controlKey;
}

/// Approved floating-surface motion on the SDK's real overlay lifecycle.
/// This is deliberately a flat menu, not a replacement for cascading menus.
/// Native viewport callbacks describe overlay visibility, including exit.
class StarBridgeMenuAnchor extends StatelessWidget {
  const StarBridgeMenuAnchor({
    required this.entries,
    required this.semanticLabel,
    this.semanticHint,
    required this.builder,
    this.enabled = true,
    this.contextMenu = false,
    this.retainExitContent = true,
    this.matchAnchorWidth = false,
    this.consumeOutsideTaps = false,
    this.onOpen,
    this.onOpenWithSource,
    this.onClose,
    this.header,
    this.maximumSize,
    this.surfaceStyle,
    super.key,
  });
  final List<StarBridgeMenuEntry> entries;
  final String semanticLabel;
  final String? semanticHint;
  final bool enabled;

  /// Secondary action on an existing control. Keep its tap/Enter/Space and
  /// read-screen role; expose this menu only as a contextual action.
  final bool contextMenu;

  /// Callers revoke this when old content is no longer allowed to be shown,
  /// e.g. an account/context invalidation. Ordinary busy updates retain exit.
  final bool retainExitContent;

  /// Choice fields stay inside their original input/protected inspector width.
  /// Ordinary action menus keep their existing intrinsic-width layout.
  final bool matchAnchorWidth;

  /// Match an original modal popup's dismissal without activating the
  /// underlying control or parent dialog barrier. Ordinary menus retain
  /// their existing pass-through policy unless the caller opts in.
  final bool consumeOutsideTaps;
  final VoidCallback? onOpen;

  /// Presentation provenance for this actual open, after [onOpen]. This does
  /// not admit an action or start a read. Direct controller opens have no
  /// proven input origin and report programmatic.
  final ValueChanged<InteractionSource>? onOpenWithSource;
  final VoidCallback? onClose;

  /// Read-only metadata, not a disabled action or a keyboard traversal target.
  final Widget? header;

  /// A caller's existing menu size cap; null retains the shared default.
  final Size? maximumSize;

  /// Preserve an existing menu family's surface without changing shared row
  /// behavior. Null retains the approved default for every other consumer.
  final MenuStyle? surfaceStyle;
  final Widget Function(
    BuildContext context,
    MenuController controller,
    FocusNode focusNode,
    ValueChanged<InteractionSource> toggle,
  )
  builder;

  @override
  Widget build(BuildContext context) =>
      StarBridgeInteractionRegion(child: _MenuCore(configuration: this));
}

/// Retire local menus before a caller hides their anchor subtree (for example
/// an IndexedStack section change). Closing after Offstage has laid out is too
/// late for the SDK portal's semantics geometry. This is presentation only:
/// no command, selection, draft or outside window is changed.
bool dismissStarBridgeMenus(BuildContext context) {
  var retired = false;
  void visit(Element element) {
    if (element is StatefulElement && element.state is _MenuCoreState) {
      final state = element.state as _MenuCoreState;
      if (state._controller.isOpen) {
        retired = true;
        state._close(InteractionSource.keyboard);
      }
    }
    element.visitChildElements(visit);
  }

  (context as Element).visitChildElements(visit);
  return retired;
}

class _MenuCore extends StatefulWidget {
  const _MenuCore({required this.configuration});
  final StarBridgeMenuAnchor configuration;
  @override
  State<_MenuCore> createState() => _MenuCoreState();
}

class _MenuCoreState extends State<_MenuCore>
    with SingleTickerProviderStateMixin {
  final _controller = MenuController();
  final _anchor = FocusNode(debugLabel: 'StarBridge-menu-anchor');
  final _rows = <Object, FocusNode>{};
  late final _animation = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.dismissed) _finishExit();
    });
  InteractionSource _source = InteractionSource.pointer;
  InteractionSource? _requestedOpenSource;
  InteractionSource _openingSource = InteractionSource.programmatic;
  VoidCallback? _hide;
  bool _closing = false;
  List<StarBridgeMenuEntry>? _exitEntries;
  Widget? _exitHeader;
  int _generation = 0;
  bool? _menuAbove, _pendingAbove;
  bool _placementScheduled = false;
  int _placementGeneration = 0;

  // The actual laid-out content (including metadata and large text) chooses
  // the side. Relay that side to the approved transition on the next frame;
  // never rebuild during layout or queue more than one placement update.
  void _reportPlacement(bool above) {
    _pendingAbove = above;
    _placementGeneration = _generation;
    if (_menuAbove == above || _placementScheduled) return;
    _placementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _placementScheduled = false;
      if (!mounted ||
          _placementGeneration != _generation ||
          !_controller.isOpen ||
          _closing) {
        return;
      }
      if (_menuAbove != _pendingAbove) {
        setState(() => _menuAbove = _pendingAbove);
      }
    });
  }

  StarBridgeMenuAnchor get config => widget.configuration;
  List<StarBridgeMenuEntry> get _displayEntries =>
      _closing && config.retainExitContent
      ? (_exitEntries ?? config.entries)
      : config.entries;
  Widget? get _displayHeader =>
      _closing && config.retainExitContent ? _exitHeader : config.header;

  @override
  void initState() {
    super.initState();
    _anchor.addListener(_refresh);
    _syncRows();
  }

  void _refresh() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _syncRows() {
    assert(
      config.entries.map((e) => e.id).toSet().length == config.entries.length,
    );
    final ids = _displayEntries.map((e) => e.id).toSet();
    var repair = false;
    for (final id in _rows.keys.toList()) {
      if (ids.contains(id)) continue;
      final node = _rows.remove(id)!;
      repair |= node.hasFocus;
      node.removeListener(_refresh);
      WidgetsBinding.instance.addPostFrameCallback((_) => node.dispose());
    }
    for (final entry in _displayEntries) {
      _rows.putIfAbsent(entry.id, () {
        return FocusNode(debugLabel: 'StarBridge-menu-${entry.id}')
          ..addListener(_refresh);
      });
      if (entry.onActivate == null && _rows[entry.id]!.hasFocus) repair = true;
    }
    if (repair) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.isOpen && !_closing) _focusFirst();
      });
    }
  }

  @override
  void didUpdateWidget(_MenuCore oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRows();
    if (_controller.isOpen &&
        ((!config.enabled && !_closing) || !config.retainExitContent)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _controller.isOpen &&
            ((!config.enabled && !_closing) || !config.retainExitContent)) {
          _close(InteractionSource.keyboard);
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final durations = surfaceDurations(
      InteractionScope.of(context),
      SurfaceKind.menu,
    );
    _animation
      ..duration = durations.enter
      ..reverseDuration = durations.exit;
    if (!InteractionScope.of(context).animates && _animation.isAnimating) {
      _animation.value = _closing ? 0 : 1;
    }
  }

  void _toggle(InteractionSource source) {
    if (!config.enabled) return;
    _source = source;
    if (_controller.isOpen && !_closing) {
      _controller.close();
    } else {
      _requestedOpenSource = source;
      _controller.open();
    }
  }

  void _openRequested(Offset? position, VoidCallback show) {
    if (!config.enabled) return;
    _openingSource = _requestedOpenSource ?? InteractionSource.programmatic;
    _requestedOpenSource = null;
    _generation++;
    _hide = null;
    _closing = false;
    _exitEntries = null;
    _exitHeader = null;
    _menuAbove = null;
    _syncRows();
    // Calling show again would make RawMenuAnchor tear down an already-open
    // overlay. Reverse the same controller instead; no stale exit can hide it.
    if (!_controller.isOpen) show();
    final data = InteractionScope.of(context);
    if (_source == InteractionSource.keyboard || !data.animates) {
      _animation.value = 1;
    } else {
      _animation.forward();
    }
    if (_source == InteractionSource.keyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.isOpen && !_closing) _focusFirst();
      });
    }
    _source = InteractionSource.pointer;
    setState(() {});
  }

  void _close(InteractionSource source) {
    _source = source;
    _controller.close();
  }

  void _closeRequested(VoidCallback hide) {
    if (!_controller.isOpen) return;
    _generation++;
    _hide = hide;
    if (config.retainExitContent) {
      _exitEntries ??= List.unmodifiable(config.entries);
      _exitHeader = config.header;
    } else {
      _exitEntries = null;
      _exitHeader = null;
    }
    _closing = true;
    _anchor.requestFocus();
    final instant =
        _source == InteractionSource.keyboard ||
        !InteractionScope.of(context).animates ||
        !config.retainExitContent;
    _source = InteractionSource.pointer;
    setState(() {});
    if (instant || _animation.value == 0) {
      _animation.value = 0;
      _finishExit();
    } else {
      _animation.reverse();
    }
  }

  void _finishExit() {
    final hide = _hide;
    if (hide == null) return;
    final generation = _generation;
    void finish() {
      if (!mounted || generation != _generation || _hide != hide) return;
      _hide = null;
      hide();
      _closing = false;
      _exitEntries = null;
      _exitHeader = null;
      _syncRows();
      _refresh();
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => finish());
    } else {
      finish();
    }
  }

  void _focusFirst() {
    for (final entry in config.entries) {
      if (entry.onActivate != null) {
        _focusRow(entry.id);
        return;
      }
    }
    _anchor.requestFocus();
  }

  void _focusRow(Object id) {
    final node = _rows[id]!;
    node.requestFocus();
    final rowContext = node.context;
    if (rowContext != null) {
      // Keyboard traversal must expose its target without a scrolling show.
      Scrollable.ensureVisible(rowContext, duration: Duration.zero);
    }
  }

  void _move(int direction) {
    if (_closing || !config.enabled) return;
    final available = config.entries
        .where((e) => e.onActivate != null)
        .toList();
    if (available.isEmpty) return;
    final current = available.indexWhere((e) => _rows[e.id]!.hasFocus);
    final index = current < 0
        ? (direction > 0 ? 0 : available.length - 1)
        : (current + direction) % available.length;
    _focusRow(available[index].id);
  }

  void _activate(Object id, InteractionSource source) {
    if (!mounted || _closing || !config.enabled) return;
    for (final entry in config.entries) {
      if (entry.id == id) {
        final action = entry.onActivate;
        if (action == null) return;
        _close(source);
        action(source);
        return;
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _hide = null;
    _animation.dispose();
    _anchor.dispose();
    for (final node in _rows.values) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _contextAnchor(BuildContext context, MenuController controller) =>
      MergeSemantics(
        child: Semantics(
          customSemanticsActions: config.enabled
              ? {
                  CustomSemanticsAction(label: config.semanticLabel): () =>
                      _toggle(InteractionSource.keyboard),
                }
              : null,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.contextMenu): () =>
                  _toggle(InteractionSource.keyboard),
              const SingleActivator(LogicalKeyboardKey.f10, shift: true): () =>
                  _toggle(InteractionSource.keyboard),
              if (controller.isOpen)
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    _close(InteractionSource.keyboard),
            },
            child: config.builder(context, controller, _anchor, _toggle),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => RawMenuAnchor(
    controller: _controller,
    childFocusNode: _anchor,
    consumeOutsideTaps: config.consumeOutsideTaps,
    onOpen: () {
      config.onOpen?.call();
      config.onOpenWithSource?.call(_openingSource);
    },
    onClose: config.onClose,
    onOpenRequested: _openRequested,
    onCloseRequested: _closeRequested,
    builder: (context, controller, _) => config.contextMenu
        ? _contextAnchor(context, controller)
        : CallbackShortcuts(
            bindings: {
              for (final key in [
                LogicalKeyboardKey.enter,
                LogicalKeyboardKey.space,
                LogicalKeyboardKey.numpadEnter,
              ])
                SingleActivator(key): () => _toggle(InteractionSource.keyboard),
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  _close(InteractionSource.keyboard),
              const SingleActivator(LogicalKeyboardKey.arrowDown): () {
                if (!controller.isOpen) _toggle(InteractionSource.keyboard);
                _move(1);
              },
            },
            child: Semantics(
              button: true,
              enabled: config.enabled,
              focused: _anchor.hasFocus,
              label: config.semanticLabel,
              hint: config.semanticHint,
              excludeSemantics: true,
              onTap: config.enabled
                  ? () => _toggle(InteractionSource.keyboard)
                  : null,
              child: config.builder(context, controller, _anchor, _toggle),
            ),
          ),
    overlayBuilder: (context, info) {
      final data = InteractionScope.of(context);
      final tokens = Theme.of(context).extension<StarBridgeTokens>();
      final radius = tokens?.shape.radiusSmall ?? 6;
      final belowSpace = (info.overlaySize.height - info.anchorRect.bottom - 14)
          .clamp(0.0, double.infinity);
      final aboveSpace = (info.anchorRect.top - 14).clamp(0.0, double.infinity);
      final above =
          belowSpace < _displayEntries.length * 40 + 8 &&
          aboveSpace > belowSpace;
      final rtl = Directionality.of(context) == TextDirection.rtl;
      return Positioned.fill(
        child: CustomSingleChildLayout(
          delegate: _MenuLayout(
            info.anchorRect,
            above: above,
            onPlacement: _reportPlacement,
            rtl: rtl,
            availableHeight: aboveSpace > belowSpace ? aboveSpace : belowSpace,
            matchAnchorWidth: config.matchAnchorWidth,
            maximumSize: config.maximumSize,
          ),
          child: TapRegion(
            groupId: info.tapRegionGroupId,
            onTapOutside: (_) => _close(InteractionSource.pointer),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    _close(InteractionSource.keyboard),
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    _move(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    _move(-1),
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
                      radius: radius,
                      alignment: Alignment(
                        rtl ? 1 : -1,
                        (_menuAbove ?? above) ? 1 : -1,
                      ),
                      child: Material(
                        animationDuration: data.animates
                            ? kThemeChangeDuration
                            : Duration.zero,
                        color:
                            config.surfaceStyle?.backgroundColor?.resolve({}) ??
                            data.palette.raised,
                        surfaceTintColor: config.surfaceStyle?.surfaceTintColor
                            ?.resolve({}),
                        shape: RoundedRectangleBorder(
                          borderRadius: suiteRadius(data.suite, radius),
                          side:
                              config.surfaceStyle?.side?.resolve({}) ??
                              BorderSide(color: data.palette.border),
                        ),
                        elevation:
                            config.surfaceStyle?.elevation?.resolve({}) ?? 8,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(4),
                          child: IntrinsicWidth(
                            child: FocusScope(
                              child: FocusTraversalGroup(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    ?_displayHeader,
                                    for (final entry in _displayEntries)
                                      _row(entry, data),
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
  );

  Widget _row(StarBridgeMenuEntry entry, InteractionData data) {
    final node = _rows[entry.id]!;
    final enabled = config.enabled && entry.onActivate != null;
    final Widget row;
    if (data.suite == InteractionSuite.standard) {
      row = Semantics(
        button: true,
        enabled: enabled,
        focused: node.hasFocus,
        selected: entry.selected,
        label: entry.label,
        excludeSemantics: true,
        onTap: enabled
            ? () => _activate(entry.id, InteractionSource.keyboard)
            : null,
        child: CallbackShortcuts(
          bindings: {
            for (final key in [
              LogicalKeyboardKey.enter,
              LogicalKeyboardKey.space,
              LogicalKeyboardKey.numpadEnter,
            ])
              SingleActivator(key): () =>
                  _activate(entry.id, InteractionSource.keyboard),
          },
          child: MenuItemButton(
            key: entry.controlKey ?? ValueKey(entry.id),
            focusNode: node,
            closeOnActivate: false,
            overflowAxis: Axis.vertical,
            onPressed: enabled
                ? () => _activate(entry.id, InteractionSource.pointer)
                : null,
            child: entry.child,
          ),
        ),
      );
    } else {
      row = SuitePressable(
        key: entry.controlKey ?? ValueKey(entry.id),
        kind: PressableKind.menuItem,
        focusNode: node,
        semanticLabel: entry.label,
        semanticSelected: entry.selected,
        minHeight: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        onActivate: enabled ? (source) => _activate(entry.id, source) : null,
        child: ExcludeSemantics(child: entry.child),
      );
    }
    return enabled
        ? MouseRegion(onHover: (_) => node.requestFocus(), child: row)
        : IgnorePointer(child: ExcludeFocus(child: row));
  }
}

class _MenuLayout extends SingleChildLayoutDelegate {
  const _MenuLayout(
    this.anchor, {
    required this.above,
    required this.onPlacement,
    required this.rtl,
    required this.availableHeight,
    required this.matchAnchorWidth,
    this.maximumSize,
  });
  final Rect anchor;
  final bool above, rtl;
  final ValueChanged<bool> onPlacement;
  final double availableHeight;
  final bool matchAnchorWidth;
  final Size? maximumSize;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: matchAnchorWidth
            ? anchor.width.clamp(
                0,
                (constraints.maxWidth - 16).clamp(0, double.infinity),
              )
            : 0,
        maxWidth: matchAnchorWidth
            ? anchor.width.clamp(
                0,
                (constraints.maxWidth - 16).clamp(0, double.infinity),
              )
            : (constraints.maxWidth - 16).clamp(0, maximumSize?.width ?? 340),
        maxHeight: availableHeight.clamp(
          0,
          (constraints.maxHeight - 16).clamp(
            0,
            maximumSize?.height ?? double.infinity,
          ),
        ),
      );
  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = rtl ? anchor.right - childSize.width : anchor.left;
    final belowSpace = (size.height - anchor.bottom - 14).clamp(
      0.0,
      double.infinity,
    );
    final aboveSpace = (anchor.top - 14).clamp(0.0, double.infinity);
    final placeAbove = childSize.height > belowSpace && aboveSpace > belowSpace;
    onPlacement(placeAbove);
    final y = placeAbove
        ? anchor.top - 6 - childSize.height
        : anchor.bottom + 6;
    return Offset(
      x.clamp(8, (size.width - childSize.width - 8).clamp(8, double.infinity)),
      y.clamp(
        8,
        (size.height - childSize.height - 8).clamp(8, double.infinity),
      ),
    );
  }

  @override
  bool shouldRelayout(_MenuLayout old) =>
      old.anchor != anchor ||
      old.above != above ||
      old.rtl != rtl ||
      old.matchAnchorWidth != matchAnchorWidth ||
      old.maximumSize != maximumSize ||
      old.availableHeight != availableHeight;
}
