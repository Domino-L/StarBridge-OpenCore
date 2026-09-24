import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'menu_overlay_frame.dart';
import 'menu_workspace_controller.dart';
import 'menu_bridge_style.dart';

@immutable
class MenuPanelContent {
  const MenuPanelContent({
    required this.id,
    required this.title,
    required this.icon,
    required this.builder,
  });
  final String id;
  final String title;
  final StarBridgeIconSemantic icon;
  final Widget Function(BuildContext context, MenuPanelLease lease) builder;
}

/// Composes the M1 frame with the M3 workspace without importing any feature.
class MenuOverlayWorkbench extends StatelessWidget {
  const MenuOverlayWorkbench({
    super.key,
    required this.controller,
    required this.panels,
    required this.contextLabel,
    required this.returnLabel,
    required this.settingsLabel,
    required this.closeLabel,
    required this.moveLabel,
    required this.resizeLabel,
    required this.onReturn,
    this.onSettings,
  });

  final MenuWorkspaceController controller;
  final List<MenuPanelContent> panels;
  final String contextLabel,
      returnLabel,
      settingsLabel,
      closeLabel,
      moveLabel,
      resizeLabel;
  final VoidCallback onReturn;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ExcludeFocus(
      excluding: !controller.visible,
      child: TickerMode(
        enabled: controller.visible,
        child: Offstage(
          offstage: !controller.visible,
          child: MenuOverlayFrame(
            contextLabel: contextLabel,
            returnLabel: returnLabel,
            settingsLabel: settingsLabel,
            onReturn: onReturn,
            onSettings: onSettings,
            tools: [
              for (final panel in panels.where((p) => controller.allows(p.id)))
                MenuOverlayTool(
                  id: panel.id,
                  label: panel.title,
                  icon: panel.icon,
                  onActivate: () => controller.open(panel.id),
                  isOpen: controller.isOpen(panel.id),
                  isActive: controller.activeId == panel.id,
                ),
            ],
            workspace: MenuOverlayWorkspace(
              controller: controller,
              panels: panels,
              closeLabel: closeLabel,
              moveLabel: moveLabel,
              resizeLabel: resizeLabel,
            ),
          ),
        ),
      ),
    ),
  );
}

class MenuOverlayWorkspace extends StatelessWidget {
  MenuOverlayWorkspace({
    super.key,
    required this.controller,
    required Iterable<MenuPanelContent> panels,
    required this.closeLabel,
    required this.moveLabel,
    required this.resizeLabel,
    this.bridgeStyle = false,
  }) : panels = Map.unmodifiable({
         for (final panel in panels) panel.id: panel,
       }) {
    if (this.panels.length != panels.length) {
      throw ArgumentError('Duplicate panel content IDs.');
    }
  }
  final MenuWorkspaceController controller;
  final Map<String, MenuPanelContent> panels;
  final String closeLabel, moveLabel, resizeLabel;
  final bool bridgeStyle;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      if (!size.isFinite || size.width <= 0 || size.height < 48) {
        return const SizedBox.shrink();
      }
      // A small display is still a desktop, not a single-panel page.
      return ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final lease in controller.openPanels)
              if (panels[lease.id] case final panel?)
                Positioned.fromRect(
                  key: ObjectKey(lease),
                  rect: controller.boundsFor(lease.id, size),
                  child: _PanelWindow(
                    controller: controller,
                    lease: lease,
                    panel: panel,
                    viewport: size,
                    compact: false,
                    active: controller.activeId == lease.id,
                    shown: controller.visible,
                    closeLabel: closeLabel,
                    moveLabel: moveLabel,
                    resizeLabel: resizeLabel,
                    bridgeStyle: bridgeStyle,
                  ),
                ),
          ],
        ),
      );
    },
  );
}

class _PanelWindow extends StatefulWidget {
  const _PanelWindow({
    required this.controller,
    required this.lease,
    required this.panel,
    required this.viewport,
    required this.compact,
    required this.active,
    required this.shown,
    required this.closeLabel,
    required this.moveLabel,
    required this.resizeLabel,
    required this.bridgeStyle,
  });
  final MenuWorkspaceController controller;
  final MenuPanelLease lease;
  final MenuPanelContent panel;
  final Size viewport;
  final bool compact, active, shown;
  final bool bridgeStyle;
  final String closeLabel, moveLabel, resizeLabel;

  @override
  State<_PanelWindow> createState() => _PanelWindowState();
}

class _PanelWindowState extends State<_PanelWindow> {
  final _focus = FocusScopeNode();
  Rect? _startBounds;
  Offset _drag = Offset.zero;
  late Widget _content = _buildContent();

  Widget _buildContent() => Builder(
    builder: (context) => widget.panel.builder(context, widget.lease),
  );

  @override
  void didUpdateWidget(covariant _PanelWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panel != widget.panel) _content = _buildContent();
    if ((!oldWidget.active || !oldWidget.shown) &&
        widget.active &&
        widget.shown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active && widget.shown) _focus.requestFocus();
      });
    }
    if (oldWidget.viewport != widget.viewport ||
        oldWidget.compact != widget.compact ||
        !widget.shown) {
      _startBounds = null;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _begin() {
    widget.controller.activate(widget.lease.id);
    _startBounds = widget.controller.boundsFor(
      widget.lease.id,
      widget.viewport,
    );
    _drag = Offset.zero;
  }

  void _update(DragUpdateDetails details, {required bool resize}) {
    final start = _startBounds;
    if (start == null || widget.compact) return;
    _drag += details.delta;
    if (resize) {
      widget.controller.resizeTo(
        widget.lease,
        Size(start.width + _drag.dx, start.height + _drag.dy),
        widget.viewport,
      );
    } else {
      widget.controller.moveTo(
        widget.lease,
        start.topLeft + _drag,
        widget.viewport,
      );
    }
  }

  void _nudge(Offset delta, bool resize) {
    final rect = widget.controller.boundsFor(widget.lease.id, widget.viewport);
    if (resize) {
      widget.controller.resizeTo(
        widget.lease,
        Size(rect.width + delta.dx, rect.height + delta.dy),
        widget.viewport,
        snap: false,
      );
    } else {
      widget.controller.moveTo(
        widget.lease,
        rect.topLeft + delta,
        widget.viewport,
        snap: false,
      );
    }
  }

  Widget _handle({required Widget child, required bool resize}) => MouseRegion(
    cursor: resize
        ? SystemMouseCursors.resizeDownRight
        : SystemMouseCursors.move,
    child: GestureDetector(
      key: ValueKey('menu-${resize ? 'resize' : 'move'}-${widget.lease.id}'),
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => _begin(),
      onPanUpdate: (details) => _update(details, resize: resize),
      onPanEnd: (_) => _startBounds = null,
      onPanCancel: () => _startBounds = null,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _nudge(const Offset(-10, 0), resize),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _nudge(const Offset(10, 0), resize),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              _nudge(const Offset(0, -10), resize),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              _nudge(const Offset(0, 10), resize),
        },
        child: widget.bridgeStyle
            ? BridgeMenuAction(
                label:
                    '${resize ? widget.resizeLabel : widget.moveLabel}: ${widget.panel.title}',
                onPressed: () => widget.controller.activate(widget.lease.id),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                child: child,
              )
            : TextButton(
                onPressed: () => widget.controller.activate(widget.lease.id),
                child: child,
              ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = widget.bridgeStyle ? null : context.tokens;
    return Offstage(
      offstage: !widget.shown,
      child: TickerMode(
        enabled: widget.shown,
        child: FocusScope(
          node: _focus,
          autofocus: widget.active && widget.shown,
          canRequestFocus: widget.active && widget.shown,
          // Explicitly restore descendants too: a scope first mounted hidden
          // must not reuse its previous effective false focusability.
          descendantsAreFocusable: widget.active && widget.shown,
          child: Listener(
            onPointerDown: (_) => widget.controller.activate(widget.lease.id),
            child: RepaintBoundary(
              child: Material(
                key: ValueKey('menu-panel-${widget.lease.id}'),
                color: widget.bridgeStyle
                    ? BridgeInk.window
                    : tokens!.surfaces.panel.fill,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    widget.bridgeStyle ? 0 : tokens!.shape.radiusMedium,
                  ),
                  side: BorderSide(
                    color: widget.bridgeStyle
                        ? (widget.active ? BridgeInk.muted : BridgeInk.line)
                        : widget.active
                        ? tokens!.colors.accent
                        : tokens!.surfaces.panel.border,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    SizedBox(
                      height: 48,
                      child: Row(
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: widget.compact
                                  ? widget.panel.title
                                  : '${widget.moveLabel}: ${widget.panel.title}',
                              child: widget.compact
                                  ? Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: widget.bridgeStyle
                                            ? 14
                                            : tokens!.space.sm,
                                      ),
                                      child: Text(
                                        widget.panel.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )
                                  : _handle(
                                      resize: false,
                                      child: Align(
                                        alignment:
                                            AlignmentDirectional.centerStart,
                                        child: Text(
                                          widget.panel.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          if (widget.bridgeStyle)
                            BridgeMenuAction(
                              key: ValueKey('menu-close-${widget.lease.id}'),
                              label:
                                  '${widget.closeLabel}: ${widget.panel.title}',
                              padding: const EdgeInsets.all(14),
                              onPressed: () =>
                                  widget.controller.close(widget.lease.id),
                              child: const MenuGlyphView(
                                MenuGlyph.close,
                                size: 16,
                              ),
                            )
                          else
                            IconButton(
                              key: ValueKey('menu-close-${widget.lease.id}'),
                              tooltip: widget.closeLabel,
                              onPressed: () =>
                                  widget.controller.close(widget.lease.id),
                              icon: const StarBridgeIcon(
                                StarBridgeIconSemantic.windowClose,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(child: ClipRect(child: _content)),
                    if (!widget.compact)
                      SizedBox(
                        height: widget.bridgeStyle ? 24 : 32,
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Tooltip(
                            message: widget.resizeLabel,
                            child: _handle(
                              resize: true,
                              child: const StarBridgeIcon(
                                StarBridgeIconSemantic.resize,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
