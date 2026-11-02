import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'painters.dart';
import 'pressable.dart';
import 'suite.dart';
import 'surface_transition.dart';

/// One row in a [SuiteMenuButton] menu.
@immutable
class SuiteMenuAction {
  const SuiteMenuAction({
    required this.label,
    this.icon,
    this.onSelected,
    this.danger = false,
    this.dividerBefore = false,
    this.children,
  });

  final String label;
  final IconData? icon;

  /// Null disables the row (shown, not focusable, no press effect).
  final VoidCallback? onSelected;

  /// Destructive action (sign out, leave): danger colour, never celebrated.
  final bool danger;
  final bool dividerBefore;

  /// Submenu rows (context menus). A row with children opens them instead
  /// of calling [onSelected].
  final List<SuiteMenuAction>? children;

  bool get enabled => onSelected != null || (children?.isNotEmpty ?? false);
}

/// A button that opens a menu anchored to it (account menu, overflow "⋯",
/// context actions). The menu opens on the anchor's [alignment] side and
/// flips its origin accordingly, so it always grows out of the button.
///
/// Pointer: suite entrance/exit. Keyboard: opens at once with focus on the
/// first enabled row; ↑/↓ move, Enter picks, Esc closes at once and gives
/// focus back to the button. Outside taps close it and still reach their
/// target. A [header] (e.g. the signed-in account) can sit above the rows.
class SuiteMenuButton extends StatefulWidget {
  const SuiteMenuButton({
    required this.anchorBuilder,
    required this.actions,
    this.header,
    this.alignment = Alignment.bottomRight,
    this.menuWidth = 220,
    this.semanticLabel,
    super.key,
  });

  /// Builds the anchor's content; [open] tells whether the menu is showing.
  final Widget Function(BuildContext context, bool open) anchorBuilder;
  final List<SuiteMenuAction> actions;
  final Widget? header;

  /// [Alignment.bottomRight]: the menu's right edge lines up with the
  /// button's right edge (top-bar account menus). [Alignment.bottomLeft]
  /// for left-aligned menus.
  final Alignment alignment;
  final double menuWidth;
  final String? semanticLabel;

  @override
  State<SuiteMenuButton> createState() => SuiteMenuButtonState();
}

class SuiteMenuButtonState extends State<SuiteMenuButton>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _anchorFocus = FocusNode(debugLabel: 'menu-anchor');
  final _rows = <FocusNode>[];
  late final _anim = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.dismissed && _portal.isShowing) {
        _portal.hide();
        if (mounted) setState(() {});
      }
    });

  bool get isOpen =>
      _portal.isShowing && _anim.status != AnimationStatus.reverse;

  @override
  void initState() {
    super.initState();
    _syncRows();
  }

  @override
  void didUpdateWidget(SuiteMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRows();
  }

  void _syncRows() {
    while (_rows.length > widget.actions.length) {
      final n = _rows.removeLast();
      WidgetsBinding.instance.addPostFrameCallback((_) => n.dispose());
    }
    while (_rows.length < widget.actions.length) {
      _rows.add(FocusNode(debugLabel: 'menu-row-${_rows.length}'));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!InteractionScope.of(context).animates && _anim.isAnimating) {
      _anim.value = _anim.status == AnimationStatus.reverse ? 0 : 1;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _anchorFocus.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void open({InteractionSource source = InteractionSource.pointer}) {
    final data = InteractionScope.of(context);
    final d = surfaceDurations(data, SurfaceKind.menu);
    _anim
      ..duration = d.enter
      ..reverseDuration = d.exit;
    _portal.show();
    setState(() {});
    if (source == InteractionSource.keyboard || !data.animates) {
      _anim.value = 1;
    } else {
      _anim.forward();
    }
    if (source == InteractionSource.keyboard) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusRow(0, 1));
    }
  }

  void close({InteractionSource source = InteractionSource.pointer}) {
    if (!_portal.isShowing) return;
    final keyboard = source == InteractionSource.keyboard;
    if (keyboard || !InteractionScope.of(context).animates) {
      _anim.value = 0;
      if (_portal.isShowing) _portal.hide();
      setState(() {});
    } else {
      _anim.reverse();
    }
    if (keyboard) _anchorFocus.requestFocus();
  }

  /// Focuses the first enabled row from [start] in direction [dir].
  void _focusRow(int start, int dir) {
    if (!mounted) return;
    for (var i = start; i >= 0 && i < widget.actions.length; i += dir) {
      if (widget.actions[i].onSelected != null) {
        _rows[i].requestFocus();
        return;
      }
    }
  }

  void _moveFocus(int dir) {
    final current = _rows.indexWhere((r) => r.hasFocus);
    _focusRow(
      current < 0 ? (dir > 0 ? 0 : widget.actions.length - 1) : current + dir,
      dir,
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final right = widget.alignment.x > 0;
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => CompositedTransformFollower(
        link: _link,
        targetAnchor: right ? Alignment.bottomRight : Alignment.bottomLeft,
        followerAnchor: right ? Alignment.topRight : Alignment.topLeft,
        offset: const Offset(0, 6),
        child: Align(
          alignment: right ? Alignment.topRight : Alignment.topLeft,
          child: InteractionScope(
            data: data,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    close(source: InteractionSource.keyboard),
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    _moveFocus(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    _moveFocus(-1),
              },
              child: TapRegion(
                groupId: _link,
                onTapOutside: (_) => close(),
                child: SuiteSurfaceTransition(
                  animation: _anim,
                  kind: SurfaceKind.menu,
                  alignment: right ? Alignment.topRight : Alignment.topLeft,
                  radius: 8,
                  child: _menu(context, data, p),
                ),
              ),
            ),
          ),
        ),
      ),
      child: CompositedTransformTarget(
        link: _link,
        child: TapRegion(
          groupId: _link,
          child: SuitePressable(
            kind: PressableKind.icon,
            focusNode: _anchorFocus,
            selected: isOpen,
            minHeight: 34,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            semanticLabel: widget.semanticLabel,
            onActivate: (s) => isOpen ? close(source: s) : open(source: s),
            builder: (context, v) => CustomPaint(
              foregroundPainter: isOpen ? _OpenMark(data) : null,
              child: widget.anchorBuilder(context, isOpen),
            ),
          ),
        ),
      ),
    );
  }

  Widget _menu(
    BuildContext context,
    InteractionData data,
    InteractionPalette p,
  ) {
    return Container(
      width: widget.menuWidth,
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
            if (widget.header != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: widget.header,
              ),
              Divider(height: 1, color: p.border.withValues(alpha: 0.5)),
              const SizedBox(height: 4),
            ],
            for (var i = 0; i < widget.actions.length; i++) ...[
              if (widget.actions[i].dividerBefore) ...[
                const SizedBox(height: 3),
                Divider(height: 1, color: p.border.withValues(alpha: 0.5)),
                const SizedBox(height: 3),
              ],
              _row(i, data, p),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(int i, InteractionData data, InteractionPalette p) {
    final a = widget.actions[i];
    final enabled = a.onSelected != null;
    final row = SuitePressable(
      kind: PressableKind.menuItem,
      focusNode: _rows[i],
      baseRadius: 5,
      minHeight: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      semanticLabel: a.label,
      onActivate: enabled
          ? (source) {
              close(source: source);
              a.onSelected!();
            }
          : null,
      builder: (context, v) {
        final color = !enabled
            ? p.textDisabled
            : a.danger
            ? p.danger
            : v.foreground;
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
          ],
        );
      },
    );
    // Danger rows keep a quiet static marker instead of any celebratory
    // effect: a thin danger edge on hover for rail/scan/glow alike.
    return a.danger && enabled ? _DangerEdge(child: row) : row;
  }
}

class _DangerEdge extends StatelessWidget {
  const _DangerEdge({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = InteractionScope.of(context).palette;
    return CustomPaint(
      foregroundPainter: _DangerPainter(p.danger),
      child: child,
    );
  }
}

class _DangerPainter extends CustomPainter {
  _DangerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 8, 2, size.height - 16),
      Paint()..color = color.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_DangerPainter old) => old.color != color;
}

/// Breadcrumb trail. Earlier crumbs are links (suite hover, no page entrance
/// when going back); the last crumb is the current page and is plain text.
class SuiteBreadcrumb extends StatelessWidget {
  const SuiteBreadcrumb({required this.crumbs, required this.onTap, super.key});

  final List<String> crumbs;
  final void Function(int index, InteractionSource source) onTap;

  @override
  Widget build(BuildContext context) {
    final p = InteractionScope.of(context).palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < crumbs.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Icon(Icons.chevron_right, size: 14, color: p.textDisabled),
            ),
          if (i == crumbs.length - 1)
            Semantics(
              header: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  crumbs[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
              ),
            )
          else
            SuitePressable(
              kind: PressableKind.tab,
              minHeight: 26,
              baseRadius: 4,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              semanticLabel: '返回${crumbs[i]}',
              onActivate: (s) => onTap(i, s),
              child: Text(crumbs[i], style: const TextStyle(fontSize: 13)),
            ),
        ],
      ],
    );
  }
}

/// Paints a short positioning tick under an anchor (shared by top-bar
/// buttons that own a menu): rail line, scan corners, glow dot.
void paintOpenMark(Canvas canvas, Rect rect, InteractionData data) {
  final p = data.palette;
  switch (data.suite) {
    case InteractionSuite.rail:
      canvas.drawRect(
        Rect.fromLTWH(rect.left + 6, rect.bottom - 2, rect.width - 12, 2),
        Paint()..color = p.edge(),
      );
    case InteractionSuite.scan:
      paintBrackets(
        canvas,
        rect.deflate(2),
        color: p.edge(),
        length: 5,
        width: 1.5,
      );
    case InteractionSuite.glow:
      paintGlowStrokes(canvas, RRect.fromRectXY(rect, 6, 6), p.accent, 0.5);
    case InteractionSuite.standard:
      break;
  }
}

class _OpenMark extends CustomPainter {
  _OpenMark(this.data);
  final InteractionData data;

  @override
  void paint(Canvas canvas, Size size) =>
      paintOpenMark(canvas, (Offset.zero & size).inflate(3), data);

  @override
  bool shouldRepaint(_OpenMark old) => old.data != data;
}
