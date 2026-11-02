import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/shell/widgets/attention_badge.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'official_fleet_holo_paint.dart';
import 'official_fleet_models.dart';

/// One entry of the top-screen section rail.
@immutable
final class OfficialFleetRailItem {
  const OfficialFleetRailItem({
    required this.section,
    required this.label,
    required this.summary,
    this.highlight = false,
    this.enabled = true,
    this.hint = '',
    this.count = 0,
    this.preview,
    this.previewFit,
    this.note = '',
  });

  final OfficialFleetWorkspaceSection section;
  final String label, summary, hint;

  /// Summary drawn in the warning colour (unread messages).
  final bool highlight;
  final bool enabled;

  /// Unread badge next to the label, as on the section tabs.
  final int count;

  /// Tall tiles only: live preview under the summary (online avatars, the
  /// current announcement, the owner state).
  final Widget? preview;

  /// Tall tiles only: a preview that adapts to the height it is given. Takes
  /// the place of [preview].
  final Widget Function(double height)? previewFit;

  /// Tall tiles without a preview: one line explaining the empty section.
  final String note;
}

/// The top screen's section rail (user decision 2026-10-22, variant A):
/// hairlines above and below, cells split by -24° dividers. Hover lights both
/// dividers, grows an underline along the slant, lifts a faint glow, nudges
/// the title and slides in "进入 ›". The last visited section keeps a faint
/// underline. Nothing is selected on the top screen itself.
class OfficialFleetSectionRail extends StatelessWidget {
  const OfficialFleetSectionRail({
    required this.items,
    required this.onSelected,
    required this.enterLabel,
    this.lastVisited,
    this.trailing,
    this.compact = false,
    super.key,
  });

  /// Page widths below this use [compact]: one row of cells plus the
  /// trailing actions no longer fit.
  static const compactBelow = 960.0;

  /// Extra height the compact layout needs over the single 96px row.
  static const compactExtra = 96.0;

  /// Below this height (times the text scale) a tall box still shows the
  /// single 96px row; above it the cells grow into section preview tiles
  /// (user decision 2026-10-22: only when the screen is tall enough).
  static const tallFrom = 150.0;

  final List<OfficialFleetRailItem> items;
  final ValueChanged<OfficialFleetWorkspaceSection> onSelected;
  final String enterLabel;
  final OfficialFleetWorkspaceSection? lastVisited;
  final Widget? trailing;

  /// Two rows of shorter cells, with the trailing actions above them.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hair = tokens.colors.textSecondary.withValues(alpha: .18);
    // Large text grows the rail instead of overflowing its cells.
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    Widget cell(int index, OfficialFleetRailItem item, {bool tall = false}) =>
        Expanded(
          child: _RailCell(
            item: item,
            first: index == 0,
            last: item.section == lastVisited,
            compact: compact,
            tall: tall,
            number: items.indexOf(item) + 1,
            enterLabel: enterLabel,
            onSelected: onSelected,
          ),
        );
    if (compact) {
      final columns = (items.length / 2).ceil();
      return Column(
        key: const Key('official-fleet-section-rail'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (trailing != null)
            SizedBox(
              height: 48 * scale,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: trailing,
              ),
            ),
          for (var row = 0; row * columns < items.length; row++)
            Container(
              height: 72 * scale,
              // Hover glows reach under neighbouring cells; clip per row.
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: hair),
                  bottom: row * columns + columns >= items.length
                      ? BorderSide(color: hair)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var column = 0; column < columns; column++)
                    if (row * columns + column < items.length)
                      cell(column, items[row * columns + column])
                    else
                      const Spacer(),
                ],
              ),
            ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final tall =
            box.maxHeight.isFinite && box.maxHeight >= tallFrom * scale;
        final row = _row(tall ? box.maxHeight : 96 * scale, hair, tall, [
          for (final (index, item) in items.indexed)
            cell(index, item, tall: tall),
        ]);
        // A short leftover keeps the plain 96px row at the top, unstretched.
        return tall ? row : Align(alignment: Alignment.topCenter, child: row);
      },
    );
  }

  Widget _row(double height, Color hair, bool tall, List<Widget> cells) =>
      Container(
        key: const Key('official-fleet-section-rail'),
        height: height,
        // Hover glows reach under neighbouring cells; the rail clips them.
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          border: Border.symmetric(horizontal: BorderSide(color: hair)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...cells,
            if (trailing != null)
              Padding(
                // Tall tiles: beside the titles, not floating mid-height.
                padding: EdgeInsetsDirectional.only(
                  start: 16,
                  top: tall ? 14 : 0,
                ),
                child: tall
                    ? Align(alignment: Alignment.topCenter, child: trailing)
                    : Center(child: trailing),
              ),
          ],
        ),
      );
}

/// The cell title: the label only, no decorative English code (user
/// 2026-10-29).
TextSpan _railLabel(BuildContext context, OfficialFleetRailItem item) =>
    TextSpan(
      text: item.label,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 2),
    );

class _RailCell extends StatefulWidget {
  const _RailCell({
    required this.item,
    required this.first,
    required this.last,
    required this.compact,
    required this.enterLabel,
    required this.onSelected,
    this.tall = false,
    this.number = 0,
  });

  final OfficialFleetRailItem item;
  final bool first, last, compact, tall;

  /// 1-based position, drawn as an outlined watermark on sparse tall tiles.
  final int number;

  final String enterLabel;
  final ValueChanged<OfficialFleetWorkspaceSection> onSelected;

  @override
  State<_RailCell> createState() => _RailCellState();
}

class _RailCellState extends State<_RailCell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lit = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  bool _hovered = false, _focused = false, _pressed = false;

  bool get _active => widget.item.enabled && (_hovered || _focused);

  void _sync() {
    final reduce = resolveStarBridgeInteraction(context).reduceMotion;
    if (reduce) {
      _lit.value = _active ? 1 : 0;
    } else if (_active) {
      _lit.forward();
    } else {
      _lit.reverse();
    }
  }

  void _activate() {
    if (widget.item.enabled) widget.onSelected(widget.item.section);
  }

  @override
  void dispose() {
    _lit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final item = widget.item;
    final accent = tokens.colors.accent;
    final cell = AnimatedBuilder(
      animation: _lit,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_lit.value);
        return CustomPaint(
          painter: _RailCellPainter(
            t: t,
            first: widget.first,
            last: widget.last,
            pressed: _pressed && item.enabled,
            focused: _focused && item.enabled,
            accent: accent,
            divider: tokens.colors.textSecondary.withValues(alpha: .28),
            tall: widget.tall,
          ),
          child: widget.tall
              ? _tile(context, t)
              : Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: widget.compact ? 18 : 26,
                    vertical: widget.compact ? 10 : 16,
                  ),
                  child: Opacity(
                    opacity: item.enabled ? 1 : .45,
                    child: Row(
                      children: [
                        Expanded(
                          child: Transform.translate(
                            offset: Offset(4 * t, 0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text.rich(
                                        _railLabel(context, item),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (item.count > 0) ...[
                                      const SizedBox(width: 8),
                                      AttentionCount(count: item.count),
                                    ],
                                  ],
                                ),
                                SizedBox(height: widget.compact ? 4 : 6),
                                Text(
                                  item.summary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall?.copyWith(
                                    color: item.highlight
                                        ? tokens.colors.warning
                                        : tokens.colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Takes no width at rest, so narrow cells keep their text.
                        ClipRect(
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: t,
                            child: Opacity(
                              opacity: t,
                              child: Transform.translate(
                                offset: Offset(-8 * (1 - t), 0),
                                child: Text(
                                  widget.enterLabel,
                                  style: text.labelMedium?.copyWith(
                                    color: accent,
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
      },
    );
    return _target(context, cell);
  }

  Widget _title(BuildContext context, double t) => Row(
    children: [
      Flexible(
        child: Text.rich(
          _railLabel(context, widget.item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      if (widget.item.count > 0) ...[
        const SizedBox(width: 8),
        AttentionCount(count: widget.item.count),
      ],
    ],
  );

  /// Tall tile: title and "进入 ›" on top, the summary, then the preview at
  /// the bottom, or the note under the summary with the outlined number.
  Widget _tile(BuildContext context, double t) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    final item = widget.item;
    final preview = item.preview, previewFit = item.previewFit;
    final hasPreview = preview != null || previewFit != null;
    return Opacity(
      opacity: item.enabled ? 1 : .45,
      child: Stack(
        children: [
          if (!hasPreview)
            PositionedDirectional(
              end: 22,
              bottom: 4,
              child: OfficialFleetOutlineText(
                widget.number.toString().padLeft(2, '0'),
                style: const TextStyle(
                  fontFamily: 'Source Sans 3',
                  fontSize: 88,
                  height: 1,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w800,
                ),
                color: tokens.colors.textPrimary.withValues(alpha: .13),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 20, 26, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Transform.translate(
                        offset: Offset(4 * t, 0),
                        child: _title(context, t),
                      ),
                    ),
                    Opacity(
                      opacity: t,
                      child: Text(
                        widget.enterLabel,
                        style: text.labelMedium?.copyWith(
                          color: tokens.colors.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: item.highlight
                        ? tokens.colors.warning
                        : tokens.colors.textSecondary,
                  ),
                ),
                if (hasPreview) ...[
                  // Sits at the bottom; a tight tile shows its top part,
                  // clipped, never an overflow.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) => Align(
                        alignment: AlignmentDirectional.bottomStart,
                        child: SingleChildScrollView(
                          primary: false,
                          physics: const NeverScrollableScrollPhysics(),
                          child:
                              previewFit?.call(
                                math.max(0, box.maxHeight - 8),
                              ) ??
                              preview,
                        ),
                      ),
                    ),
                  ),
                ] else if ((item.enabled ? item.note : item.hint)
                    .isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    // A disabled section explains why instead.
                    item.enabled ? item.note : item.hint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: tokens.colors.textDisabled,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _target(BuildContext context, Widget cell) {
    final item = widget.item;
    return Semantics(
      button: true,
      enabled: item.enabled,
      hint: item.enabled ? null : item.hint,
      child: FocusableActionDetector(
        key: Key('official-fleet-tab-${item.section.name}'),
        enabled: item.enabled,
        mouseCursor: item.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (value) {
          setState(() => _hovered = value);
          _sync();
        },
        onShowFocusHighlight: (value) {
          setState(() => _focused = value);
          _sync();
        },
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: _activate,
          child: item.hint.isEmpty || item.enabled
              ? cell
              : Tooltip(message: item.hint, child: cell),
        ),
      ),
    );
  }
}

class _RailCellPainter extends CustomPainter {
  const _RailCellPainter({
    required this.t,
    required this.first,
    required this.last,
    required this.pressed,
    required this.focused,
    required this.accent,
    required this.divider,
    this.tall = false,
  });

  final double t;
  final bool first, last, pressed, focused, tall;
  final Color accent, divider;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 18.0;
    final run = (size.height - inset * 2) * officialFleetHoloSlant / 2;
    if (tall) {
      _paintTall(canvas, size);
      return;
    }
    // Glow between the two slanted dividers, rising from the bottom.
    if (t > 0) {
      final glowRun = size.height * officialFleetHoloSlant / 2;
      final glow = Path()
        ..moveTo(glowRun, 0)
        ..lineTo(size.width + glowRun, 0)
        ..lineTo(size.width - glowRun, size.height)
        ..lineTo(-glowRun, size.height)
        ..close();
      // Not clipped to this cell: the slanted edges reach under the
      // neighbours, the rail as a whole clips at its own bounds.
      canvas.drawPath(
        glow,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: 0),
              accent.withValues(alpha: (pressed ? .07 : .12) * t),
            ],
            stops: const [.3, 1],
          ).createShader(Offset.zero & size),
      );
    }
    // Dividers: the left one belongs to this cell; the right one is only
    // drawn lit, over the neighbour's own resting divider. Lit dividers grow
    // to both hairlines with the hover, so they stay on the glow's slanted
    // edges instead of stopping short of its corners.
    Path slant(double x, {bool lit = false}) {
      final end = lit ? inset * (1 - t) : inset;
      final reach = lit
          ? (size.height / 2 - end) * officialFleetHoloSlant
          : run;
      return Path()
        ..moveTo(x + reach, end)
        ..lineTo(x - reach, size.height - end);
    }

    final rest = Paint()
      ..color = divider
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final lit = Paint()
      ..color = Color.lerp(divider, accent.withValues(alpha: .85), t)!
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    if (t > 0) {
      canvas.drawPath(slant(0, lit: true), lit);
      canvas.drawPath(slant(size.width, lit: true), lit);
    } else if (!first) {
      canvas.drawPath(slant(0), rest);
    }
    // Underline along the slant: grows on hover, faint for the last visit.
    final grow = math.max(t, last ? 1.0 : 0.0);
    if (grow > 0) {
      const side = 26.0;
      final height = pressed ? 3.0 : 2.0;
      final width = (size.width - side * 2) * grow;
      final line = Path()
        ..moveTo(side + 3, size.height - height)
        ..lineTo(side + width, size.height - height)
        ..lineTo(side + width - 3, size.height)
        ..lineTo(side, size.height)
        ..close();
      canvas.drawPath(
        line,
        Paint()..color = t > 0 ? accent : accent.withValues(alpha: .35),
      );
    }
    if (focused) {
      final rect = (Offset.zero & size).deflate(6);
      final dash = Paint()
        ..color = accent.withValues(alpha: .7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      for (final (from, to) in [
        (rect.topLeft, rect.topRight),
        (rect.topRight, rect.bottomRight),
        (rect.bottomRight, rect.bottomLeft),
        (rect.bottomLeft, rect.topLeft),
      ]) {
        final length = (to - from).distance;
        final step = (to - from) / length;
        for (var at = 0.0; at < length; at += 8) {
          canvas.drawLine(
            from + step * at,
            from + step * math.min(at + 4, length),
            dash,
          );
        }
      }
    }
  }

  /// Tall tiles: the slant only beside the 64px title band (a full-height
  /// -24° line would run ~100px sideways through the preview), a plain
  /// rising glow, and the same underline.
  void _paintTall(Canvas canvas, Size size) {
    const top = 18.0, band = 64.0;
    final run = band * officialFleetHoloSlant / 2;
    if (t > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              accent.withValues(alpha: 0),
              accent.withValues(alpha: (pressed ? .06 : .10) * t),
            ],
            stops: const [.3, 1],
          ).createShader(Offset.zero & size),
      );
    }
    final line = Paint()
      ..color = t > 0
          ? Color.lerp(divider, accent.withValues(alpha: .85), t)!
          : divider
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    Path slant(double x) => Path()
      ..moveTo(x + run, top)
      ..lineTo(x - run, top + band);
    if (!first || t > 0) canvas.drawPath(slant(0), line);
    if (t > 0) canvas.drawPath(slant(size.width), line);
    final grow = math.max(t, last ? 1.0 : 0.0);
    if (grow > 0) {
      const side = 26.0;
      final height = pressed ? 3.0 : 2.0;
      final width = (size.width - side * 2) * grow;
      canvas.drawPath(
        Path()
          ..moveTo(side + 3, size.height - height)
          ..lineTo(side + width, size.height - height)
          ..lineTo(side + width - 3, size.height)
          ..lineTo(side, size.height)
          ..close(),
        Paint()..color = t > 0 ? accent : accent.withValues(alpha: .35),
      );
    }
    if (focused) {
      canvas.drawRect(
        (Offset.zero & size).deflate(6),
        Paint()
          ..color = accent.withValues(alpha: .7)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_RailCellPainter old) =>
      old.tall != tall ||
      old.t != t ||
      old.first != first ||
      old.last != last ||
      old.pressed != pressed ||
      old.focused != focused ||
      old.accent != accent ||
      old.divider != divider;
}
