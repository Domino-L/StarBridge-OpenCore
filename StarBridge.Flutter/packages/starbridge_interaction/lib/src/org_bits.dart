import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'field.dart';
import 'painters.dart';
import 'pressable.dart';
import 'suite.dart';

// ---------------------------------------------------------------------------
// 16 · high-risk confirmation
// ---------------------------------------------------------------------------

/// Body of a destructive confirmation (remove member, transfer ownership,
/// leave organisation). States the consequences, can require typing a name,
/// and keeps the confirm button disabled until it matches.
///
/// The warning mark is static in every suite (rail: a danger rail on the
/// leading edge, scan: danger corner brackets, glow: a contained danger
/// edge, standard: an icon band). Nothing celebrates or pulses: motion never
/// stands in for the confirmation itself.
class SuiteDangerConfirm extends StatefulWidget {
  const SuiteDangerConfirm({
    required this.title,
    required this.consequences,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    this.typeToConfirm,
    super.key,
  });

  final String title;
  final List<String> consequences;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  /// When set, the user must type this text before confirming.
  final String? typeToConfirm;

  @override
  State<SuiteDangerConfirm> createState() => _SuiteDangerConfirmState();
}

class _SuiteDangerConfirmState extends State<SuiteDangerConfirm> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  bool get _ok =>
      widget.typeToConfirm == null || _text.text.trim() == widget.typeToConfirm;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    return CustomPaint(
      foregroundPainter: _DangerMark(data),
      child: Container(
        width: 320,
        padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
        decoration: BoxDecoration(
          color: p.raised,
          borderRadius: suiteRadius(data.suite, 9),
          border: Border.all(color: p.danger.withValues(alpha: 0.7)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Row(
              spacing: 8,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: p.danger),
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            for (final c in widget.consequences)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 6,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(width: 4, height: 4, color: p.danger),
                  ),
                  Expanded(
                    child: Text(
                      c,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: p.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            if (widget.typeToConfirm != null) ...[
              Text(
                '请输入「${widget.typeToConfirm}」确认',
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
              SuiteFieldFrame(
                focusNode: _focus,
                height: 32,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Center(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      style: TextStyle(fontSize: 13, color: p.textPrimary),
                      decoration: const InputDecoration.collapsed(hintText: ''),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                SuitePressable(
                  kind: PressableKind.secondary,
                  autofocus: widget.typeToConfirm == null,
                  minHeight: 30,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  onPressed: widget.onCancel,
                  child: const Text('取消', style: TextStyle(fontSize: 13)),
                ),
                SuitePressable(
                  kind: PressableKind.danger,
                  minHeight: 30,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  onPressed: _ok ? widget.onConfirm : null,
                  child: Text(
                    widget.confirmLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DangerMark extends CustomPainter {
  _DangerMark(this.data);
  final InteractionData data;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    final rect = Offset.zero & size;
    switch (data.suite) {
      case InteractionSuite.rail:
        canvas.drawRect(
          Rect.fromLTWH(0, 10, 3, size.height - 20),
          Paint()..color = p.danger,
        );
      case InteractionSuite.scan:
        paintBrackets(
          canvas,
          rect.inflate(4),
          color: p.danger,
          length: 12,
          width: 2,
        );
      case InteractionSuite.glow:
        // Contained: one faint stroke, no bloom.
        canvas.drawRRect(
          suiteRadius(data.suite, 9).toRRect(rect).inflate(2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = p.danger.withValues(alpha: 0.35),
        );
      case InteractionSuite.standard:
        break;
    }
  }

  @override
  bool shouldRepaint(_DangerMark old) => old.data != data;
}

// ---------------------------------------------------------------------------
// 23 · chart
// ---------------------------------------------------------------------------

@immutable
class ChartSeries {
  const ChartSeries({
    required this.name,
    required this.values,
    required this.color,
  });
  final String name;
  final List<double> values;
  final Color color;
}

/// Grouped bar chart with a legend that toggles series. Real values are
/// shown as they are (no tweened, made-up intermediate bars); hovering a
/// group shows its values right away and the readout never chases an
/// animation. Hover mark: rail draws a guide line, scan brackets the group,
/// glow lights it softly. Keyboard: the legend chips are focusable buttons.
class SuiteBarChart extends StatefulWidget {
  const SuiteBarChart({
    required this.labels,
    required this.series,
    this.height = 160,
    super.key,
  });

  final List<String> labels;
  final List<ChartSeries> series;
  final double height;

  @override
  State<SuiteBarChart> createState() => SuiteBarChartState();
}

class SuiteBarChartState extends State<SuiteBarChart> {
  final hidden = <String>{};
  int? hover;

  @override
  Widget build(BuildContext context) {
    final data = InteractionScope.of(context);
    final p = data.palette;
    final visible = widget.series
        .where((s) => !hidden.contains(s.name))
        .toList();
    final maxV = math.max(
      1.0,
      visible.expand((s) => s.values).fold<double>(0, math.max),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Wrap(
          spacing: 6,
          children: [
            for (final s in widget.series)
              Semantics(
                toggled: !hidden.contains(s.name),
                child: SuitePressable(
                  kind: PressableKind.tab,
                  selected: !hidden.contains(s.name),
                  minHeight: 24,
                  baseRadius: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  semanticLabel: s.name,
                  onPressed: () => setState(
                    () => hidden.contains(s.name)
                        ? hidden.remove(s.name)
                        : hidden.add(s.name),
                  ),
                  builder: (context, v) => Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 5,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: hidden.contains(s.name)
                              ? Colors.transparent
                              : s.color,
                          border: Border.all(color: s.color),
                          shape: data.suite == InteractionSuite.scan
                              ? BoxShape.rectangle
                              : BoxShape.circle,
                        ),
                      ),
                      Text(
                        s.name,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: hidden.contains(s.name)
                              ? p.textDisabled
                              : v.foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, c) {
              final groupW = c.maxWidth / widget.labels.length;
              return MouseRegion(
                onHover: (e) => setState(
                  () => hover = (e.localPosition.dx / groupW).floor().clamp(
                    0,
                    widget.labels.length - 1,
                  ),
                ),
                onExit: (_) => setState(() => hover = null),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ChartPainter(
                          data,
                          widget.labels,
                          visible,
                          maxV,
                          hover,
                          DefaultTextStyle.of(context).style,
                        ),
                      ),
                    ),
                    if (hover != null && visible.isNotEmpty)
                      Positioned(
                        left: (groupW * hover! + groupW / 2 - 50).clamp(
                          0.0,
                          c.maxWidth - 100,
                        ),
                        top: 0,
                        child: IgnorePointer(
                          child: Container(
                            width: 100,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: p.isDark
                                  ? const Color(0xEE22313B)
                                  : const Color(0xEE26343D),
                              borderRadius: suiteRadius(data.suite, 4),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.labels[hover!],
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFEFF5F8),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                for (final s in visible)
                                  Text(
                                    '${s.name} ${s.values[hover!].round()}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFFEFF5F8),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(
    this.data,
    this.labels,
    this.series,
    this.maxV,
    this.hover,
    this.base,
  );
  final InteractionData data;
  final List<String> labels;
  final List<ChartSeries> series;
  final double maxV;
  final int? hover;

  /// Page text style, so axis labels use the app fonts and fallbacks.
  final TextStyle base;

  @override
  void paint(Canvas canvas, Size size) {
    final p = data.palette;
    const labelH = 16.0;
    final plotH = size.height - labelH;
    final groupW = size.width / labels.length;
    final grid = Paint()..color = p.border.withValues(alpha: 0.25);
    for (var i = 1; i <= 3; i++) {
      canvas.drawRect(Rect.fromLTWH(0, plotH * i / 4, size.width, 1), grid);
    }
    for (var g = 0; g < labels.length; g++) {
      final gx = g * groupW;
      if (hover == g) {
        final band = Rect.fromLTWH(gx + 2, 0, groupW - 4, plotH);
        switch (data.suite) {
          case InteractionSuite.rail:
            canvas.drawRect(
              Rect.fromLTWH(gx + groupW / 2 - 0.5, 0, 1, plotH),
              Paint()..color = p.edge(0.7),
            );
          case InteractionSuite.scan:
            paintBrackets(
              canvas,
              band,
              color: p.edge(0.8),
              length: 6,
              width: 1.5,
            );
          case InteractionSuite.glow:
            canvas.drawRect(
              band,
              Paint()
                ..shader = RadialGradient(colors: [p.light(0.18), p.light(0)])
                    .createShader(band),
            );
          case InteractionSuite.standard:
            canvas.drawRect(band, Paint()..color = p.light(0.06));
        }
      }
      final n = math.max(1, series.length);
      final barW = math.min(14.0, (groupW - 12) / n);
      final startX = gx + (groupW - barW * n - 2 * (n - 1)) / 2;
      for (var s = 0; s < series.length; s++) {
        final h = plotH * (series[s].values[g] / maxV);
        final r = Rect.fromLTWH(startX + s * (barW + 2), plotH - h, barW, h);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            r,
            topLeft: Radius.circular(
              data.suite == InteractionSuite.scan ? 0 : 2,
            ),
            topRight: Radius.circular(
              data.suite == InteractionSuite.scan ? 0 : 2,
            ),
          ),
          Paint()
            ..color = series[s].color.withValues(
              alpha: hover == null || hover == g ? 1 : 0.55,
            ),
        );
      }
      final tp = TextPainter(
        text: TextSpan(
          text: labels[g],
          style: base.copyWith(fontSize: 10.5, color: p.textSecondary),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: groupW);
      tp.paint(canvas, Offset(gx + (groupW - tp.width) / 2, plotH + 2));
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}
