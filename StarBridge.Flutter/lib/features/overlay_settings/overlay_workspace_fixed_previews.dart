import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/styles/overlay_preview_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_layout_geometry.dart';
import 'overlay_workspace_preview_content.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_runtime_projection.dart';

/// Non-rectangular WPF modules share their settings between both canvases.
class OverlayWorkspaceFixedPreviews extends StatelessWidget {
  const OverlayWorkspaceFixedPreviews({
    required this.settings,
    this.onSelected,
    this.onEventNotificationPlacement,
    this.onEventNotificationGestureStart,
    this.onEventNotificationGestureEnd,
    this.eventNotificationSnapPixels = 0,
    this.eventNotificationSmartSnap = true,
    this.chatTextOpacity = 1,
    this.simulate = false,
    this.surfaceSize = OverlayWorkspaceLayoutGeometry.referenceSize,
    super.key,
  });
  final OverlayWorkspaceSettings settings;
  final bool simulate;
  final Size surfaceSize;
  final ValueChanged<String>? onSelected;
  final void Function(String side, double normalizedY)?
  onEventNotificationPlacement;
  final VoidCallback? onEventNotificationGestureStart;
  final VoidCallback? onEventNotificationGestureEnd;
  final double eventNotificationSnapPixels;
  final bool eventNotificationSmartSnap;
  final double chatTextOpacity;
  @override
  Widget build(BuildContext context) {
    final visible = OverlayWorkspaceRuntimeProjection.resolveVisibility(
      settings,
      noticeHasContent: true,
      chatHasContent: true,
      eventNotificationsHaveContent: true,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(
          constraints.maxWidth / surfaceSize.width,
          constraints.maxHeight / surfaceSize.height,
        );
        final scaledSurface = Size(
          surfaceSize.width * scale,
          surfaceSize.height * scale,
        );
        final surfaceOffset = Offset(
          (constraints.maxWidth - scaledSurface.width) / 2,
          (constraints.maxHeight - scaledSurface.height) / 2,
        );
        final size = (settings['crosshairSize']! as num).toDouble();
        final eventRect =
            OverlayWorkspaceLayoutGeometry.resolveEventNotificationRect(
              surfaceWidth: surfaceSize.width,
              surfaceHeight: surfaceSize.height,
              side: settings['eventNotificationSide']! as String,
              normalizedY: (settings['eventNotificationY']! as num).toDouble(),
              preferredHeight: OverlayWorkspaceLayoutGeometry
                  .singleEventNotificationPlacementHeight,
            );
        return Stack(
          children: [
            if (simulate &&
                visible.showChat &&
                settings['chatDisplayMode'] == 'FullScreenBarrage')
              Positioned(
                left: surfaceOffset.dx,
                top: surfaceOffset.dy,
                width: scaledSurface.width,
                height: scaledSurface.height,
                child: IgnorePointer(
                  child: FittedBox(
                    fit: BoxFit.fill,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: surfaceSize.width,
                      height: surfaceSize.height,
                      child: _BarragePreview(
                        settings: settings,
                        textOpacity: chatTextOpacity,
                      ),
                    ),
                  ),
                ),
              ),
            if (visible.showCrosshair)
              Center(
                child: GestureDetector(
                  onTap: onSelected == null
                      ? null
                      : () => onSelected!('crosshair'),
                  behavior: HitTestBehavior.opaque,
                  child: Opacity(
                    opacity: (settings['crosshairOpacity']! as num).toDouble(),
                    child: CustomPaint(
                      key: const Key('overlay-runtime-preview-crosshair'),
                      size: Size.square(size * scale),
                      painter: OverlayCrosshairPainter(settings),
                    ),
                  ),
                ),
              ),
            if (visible.showEventNotifications)
              Positioned(
                left: surfaceOffset.dx + eventRect.left * scale,
                top: surfaceOffset.dy + eventRect.top * scale,
                width: eventRect.width * scale,
                height:
                    OverlayWorkspaceLayoutGeometry
                        .singleEventNotificationPreviewHeight *
                    scale,
                child: _EventNotificationPreview(
                  settings: settings,
                  eventRect: eventRect,
                  surfaceSize: surfaceSize,
                  scaleX: scale,
                  scaleY: scale,
                  snapPixels: eventNotificationSnapPixels,
                  smartSnap: eventNotificationSmartSnap,
                  simulate: simulate,
                  onSelected: onSelected,
                  onPlacementChanged: onEventNotificationPlacement,
                  onGestureStart: onEventNotificationGestureStart,
                  onGestureEnd: onEventNotificationGestureEnd,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EventNotificationPreview extends StatefulWidget {
  const _EventNotificationPreview({
    required this.settings,
    required this.eventRect,
    required this.surfaceSize,
    required this.scaleX,
    required this.scaleY,
    required this.snapPixels,
    required this.smartSnap,
    required this.simulate,
    this.onSelected,
    this.onPlacementChanged,
    this.onGestureStart,
    this.onGestureEnd,
  });

  final OverlayWorkspaceSettings settings;
  final Rect eventRect;
  final Size surfaceSize;
  final double scaleX;
  final double scaleY;
  final double snapPixels;
  final bool smartSnap;
  final bool simulate;
  final ValueChanged<String>? onSelected;
  final void Function(String side, double normalizedY)? onPlacementChanged;
  final VoidCallback? onGestureStart;
  final VoidCallback? onGestureEnd;

  @override
  State<_EventNotificationPreview> createState() =>
      _EventNotificationPreviewState();
}

class _EventNotificationPreviewState extends State<_EventNotificationPreview> {
  int? _pointer;
  double? _rawTop;
  double? _pointerX;

  void _start(PointerDownEvent event) {
    if ((event.buttons & kPrimaryMouseButton) == 0 || _pointer != null) return;
    widget.onSelected?.call('events');
    if (widget.onPlacementChanged == null) return;
    _pointer = event.pointer;
    _rawTop = widget.eventRect.top;
    _pointerX =
        widget.eventRect.left +
        event.localPosition.dx / widget.scaleX.clamp(0.0001, double.infinity);
    widget.onGestureStart?.call();
  }

  void _update(PointerMoveEvent event) {
    if (event.pointer != _pointer || _rawTop == null || _pointerX == null) {
      return;
    }
    _rawTop =
        _rawTop! +
        event.delta.dy / widget.scaleY.clamp(0.0001, double.infinity);
    _pointerX =
        _pointerX! +
        event.delta.dx / widget.scaleX.clamp(0.0001, double.infinity);
    final minTop =
        OverlayWorkspaceLayoutGeometry.eventNotificationVerticalInset;
    final maxTop = math.max(
      minTop,
      widget.surfaceSize.height -
          widget.eventRect.height -
          OverlayWorkspaceLayoutGeometry.eventNotificationVerticalInset,
    );
    final available = math.max(1.0, maxTop - minTop);
    var top = _rawTop!.clamp(minTop, maxTop).toDouble();
    if (widget.snapPixels > 0) {
      top = (top / widget.snapPixels).round() * widget.snapPixels;
    }
    if (widget.smartSnap) {
      final centeredTop = minTop + available / 2;
      for (final target in [minTop, centeredTop, maxTop]) {
        if ((top - target).abs() <=
            OverlayWorkspaceLayoutGeometry.edgeSnapThreshold) {
          top = target;
          break;
        }
      }
    }
    top = top.clamp(minTop, maxTop).toDouble();
    widget.onPlacementChanged!(
      _pointerX! < widget.surfaceSize.width / 2 ? 'Left' : 'Right',
      ((top - minTop) / available).clamp(0.0, 1.0).toDouble(),
    );
  }

  void _end(int pointer) {
    if (pointer != _pointer || _rawTop == null) return;
    _pointer = null;
    _rawTop = null;
    _pointerX = null;
    widget.onGestureEnd?.call();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: AppStrings.of(context).text('overlay.preview.eventDrag'),
    child: MouseRegion(
      cursor: widget.onPlacementChanged == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.move,
      child: Listener(
        key: const Key('overlay-runtime-preview-event'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: _start,
        onPointerMove: _update,
        onPointerUp: (event) => _end(event.pointer),
        onPointerCancel: (event) => _end(event.pointer),
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: widget.eventRect.width,
            height: OverlayWorkspaceLayoutGeometry
                .singleEventNotificationPreviewHeight,
            child: OverlayPreviewModuleSurface(
              settings: widget.settings,
              backgroundOpacity:
                  (widget.settings['eventNotificationBackgroundOpacity']!
                          as num)
                      .toDouble(),
              textOpacity:
                  (widget.settings['eventNotificationTextOpacity']! as num)
                      .toDouble(),
              decorationOpacity:
                  (widget.settings['eventNotificationDecorationOpacity']!
                          as num)
                      .toDouble(),
              child: OverlayPreviewContent(
                moduleKey: 'Events',
                settings: widget.settings,
                referenceSize: Size(
                  widget.eventRect.width,
                  OverlayWorkspaceLayoutGeometry
                      .singleEventNotificationPreviewHeight,
                ),
                simulate: widget.simulate,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _BarragePreview extends StatelessWidget {
  const _BarragePreview({required this.settings, required this.textOpacity});

  final OverlayWorkspaceSettings settings;
  final double textOpacity;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final strings = AppStrings.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        final fontSize = (settings['chatBarrageFontSize']! as num).toDouble();
        const lanes = 2;
        final positions = [height * 0.38, height * 0.62];
        final edge = switch (settings['chatTextEdgeStrength']) {
          'Strong' => 3.0,
          'Standard' => 2.0,
          'Light' => 1.0,
          _ => 0.0,
        };
        final samples = [
          (strings.text('overlay.sample.barrage1'), '21:14'),
          (strings.text('overlay.sample.barrage2'), '21:15'),
          (strings.text('overlay.sample.barrage3'), '21:16'),
        ];
        return Stack(
          key: const Key('overlay-runtime-preview-barrage'),
          clipBehavior: Clip.hardEdge,
          children: List.generate(lanes, (index) {
            final sample = samples[index % samples.length];
            final showSender = settings['chatShowSender'] == true;
            final showTime = settings['chatShowTimestamp'] == true;
            final sender = showSender
                ? strings.text('overlay.sample.sender')
                : strings.text('overlay.sample.communicationMessage');
            final senderStyle = _barrageStyle(
              color: tokens.colors.accent,
              fontSize: fontSize,
              edge: edge,
              weight: FontWeight.w700,
            );
            final messageStyle = _barrageStyle(
              color: tokens.colors.textPrimary,
              fontSize: fontSize,
              edge: edge,
              weight: FontWeight.w600,
            );
            final timeStyle = _barrageStyle(
              color: tokens.colors.textSecondary,
              fontSize: fontSize * 0.72,
              edge: edge,
            );
            final direction = Directionality.of(context);
            final scaler = MediaQuery.textScalerOf(context);
            final laneWidth =
                3 +
                8 +
                _measureTextWidth(sender, senderStyle, direction, scaler) +
                9 +
                _measureTextWidth(sample.$1, messageStyle, direction, scaler) +
                (showTime
                    ? 9 +
                          _measureTextWidth(
                            sample.$2,
                            timeStyle,
                            direction,
                            scaler,
                          )
                    : 0) +
                edge * 2 +
                2;
            final targetLeft = width * (index == 0 ? 0.30 : 0.56);
            final left = targetLeft
                .clamp(
                  width * 0.22,
                  math.max(width * 0.22, width * 0.78 - laneWidth),
                )
                .toDouble();
            return Positioned(
              key: Key('overlay-runtime-preview-barrage-lane-$index'),
              left: left,
              top: positions[index],
              width: laneWidth,
              child: Opacity(
                opacity: textOpacity.clamp(0.0, 1.0),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: fontSize * 1.2,
                      color: tokens.colors.accent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      sender,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: senderStyle,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      sample.$1,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: messageStyle,
                    ),
                    if (showTime) ...[
                      const SizedBox(width: 9),
                      Opacity(
                        opacity: 0.72,
                        child: Text(
                          sample.$2,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: timeStyle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }

  static TextStyle _barrageStyle({
    required Color color,
    required double fontSize,
    required double edge,
    FontWeight weight = FontWeight.normal,
  }) => TextStyle(
    color: color,
    fontSize: fontSize,
    fontWeight: weight,
    height: 1,
    shadows: edge == 0
        ? null
        : [
            Shadow(
              color: Colors.black.withValues(alpha: 0.92),
              blurRadius: edge,
            ),
          ],
  );

  static double _measureTextWidth(
    String text,
    TextStyle style,
    TextDirection direction,
    TextScaler scaler,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}

/// Geometry is aligned with WPF CreateCrosshairPreview, including outline.
class OverlayCrosshairPainter extends CustomPainter {
  const OverlayCrosshairPainter(this.settings);
  final OverlayWorkspaceSettings settings;
  double number(String key) => (settings[key]! as num).toDouble();
  @override
  void paint(Canvas canvas, Size viewport) {
    final size = number('crosshairSize');
    if (size <= 0) return;
    canvas.save();
    canvas.scale(viewport.width / size, viewport.height / size);
    final center = size / 2;
    final thickness = number('crosshairThickness').clamp(1.0, 8.0);
    final normalizedGap = number('crosshairGap');
    final gap = math.min(size / 2 - 0.5, normalizedGap * size / 96);
    final arm = ((38 - normalizedGap) * size / 96).clamp(
      size * 0.12,
      size * 0.32,
    );
    final color = overlayCrosshairColor(
      settings['theme']! as String,
      settings['crosshairUseThemeColor'] == true,
      settings['crosshairColor']! as String,
    );
    final outline = Colors.black.withValues(
      alpha: number('crosshairOutlineOpacity').clamp(0.0, 1.0),
    );
    final stroke = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final edge = Paint()
      ..color = outline
      ..strokeWidth = thickness + 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    void dot() {
      final diameter = number('crosshairCenterMarkSize');
      canvas.drawCircle(
        Offset(center, center),
        (diameter + math.max(2, thickness * 0.7)) / 2,
        Paint()..color = outline,
      );
      canvas.drawCircle(
        Offset(center, center),
        diameter / 2,
        Paint()..color = color,
      );
    }

    void line(Offset from, Offset to) {
      canvas.drawLine(from, to, edge);
      canvas.drawLine(from, to, stroke);
    }

    final mode = settings['crosshairMode'];
    if (mode == 'Dot') {
      dot();
    } else {
      if (mode == 'Circle') {
        final radius = (size * 0.62).clamp(8, math.max(8, size - 4)) / 2;
        canvas.drawCircle(Offset(center, center), radius, edge);
        canvas.drawCircle(Offset(center, center), radius, stroke);
      } else {
        if (mode != 'TShape') {
          line(
            Offset(center, center - gap - arm),
            Offset(center, center - gap),
          );
        }
        line(Offset(center, center + gap), Offset(center, center + gap + arm));
        line(Offset(center - gap - arm, center), Offset(center - gap, center));
        line(Offset(center + gap, center), Offset(center + gap + arm, center));
      }
      if (settings['crosshairShowCenterMark'] == true) dot();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(OverlayCrosshairPainter oldDelegate) =>
      oldDelegate.settings != settings;
}
