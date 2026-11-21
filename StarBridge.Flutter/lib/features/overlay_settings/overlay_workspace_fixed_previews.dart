import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/styles/overlay_preview_palette.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_workspace_layout_geometry.dart';
import 'overlay_preview_sources.dart';
import 'overlay_workspace_models.dart';
import 'overlay_workspace_runtime_projection.dart';
import 'overlay_event_notification_preview.dart';
import 'overlay_visor_layout.dart';
import 'overlay_visor_projection.dart';

/// Non-rectangular WPF modules share their settings between both canvases.
class OverlayWorkspaceFixedPreviews extends StatelessWidget {
  const OverlayWorkspaceFixedPreviews({
    required this.settings,
    this.onSelected,
    this.selectionOnly = false,
    this.onEventNotificationPlacement,
    this.onEventNotificationGestureStart,
    this.onEventNotificationGestureEnd,
    this.eventNotificationSnapPixels = 0,
    this.eventNotificationSmartSnap = true,
    this.chatTextOpacity = 1,
    this.simulate = false,
    this.surfaceSize = OverlayWorkspaceLayoutGeometry.referenceSize,
    this.layout = const [],
    super.key,
  });
  final OverlayWorkspaceSettings settings;

  /// The saved layout: with the visor the event preview sits where the visor
  /// shows the events (review R6); the chat preview takes the chat module's
  /// text opacity from it (else [chatTextOpacity]).
  final List<OverlayWorkspaceLayoutItem> layout;
  final bool simulate;
  final Size surfaceSize;
  final ValueChanged<String>? onSelected;
  final bool selectionOnly;
  final void Function(String side, double normalizedY, {double? x})?
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
        final moduleEventRect =
            OverlayWorkspaceLayoutGeometry.resolveEventNotificationRect(
              surfaceWidth: surfaceSize.width,
              surfaceHeight: surfaceSize.height,
              side: settings['eventNotificationSide']! as String,
              // The visor shows untouched events at the top of its right column.
              normalizedY: OverlayVisorLayout.eventDisplayY(
                settings,
                surfaceSize,
              ),
              preferredHeight: OverlayWorkspaceLayoutGeometry
                  .singleEventNotificationPlacementHeight,
            );
        // with the visor, the events block is the visor's own events box: its
        // size follows the most events at once and it leans like the visor
        // draws it (11-11 user: "跟用户选择的最大同时事件挂钩", "同样的3d效果")
        final visorEvents = OverlayVisorLayout.active(settings)
            ? OverlayVisorLayout.eventsPlacement(layout, settings, surfaceSize)
            : null;
        final eventRect = visorEvents ?? moduleEventRect;
        final eventsTilt = visorEvents == null
            ? null
            : OverlayVisorProjection.tilts(
                layout,
                settings,
                surfaceSize,
              )['Events'];
        final tiltDegrees = OverlayVisorProjection.degrees(settings);
        return Stack(
          children: [
            if (simulate &&
                visible.showChat &&
                OverlayPreviewSourceScope.of(context, 'Chat')?.unavailable !=
                    true &&
                settings['chatDisplayMode'] == 'FullScreenBarrage')
              Positioned(
                left: surfaceOffset.dx,
                top: surfaceOffset.dy,
                width: scaledSurface.width,
                height: scaledSurface.height,
                child: IgnorePointer(
                  ignoring: !selectionOnly,
                  child: FittedBox(
                    fit: BoxFit.fill,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: surfaceSize.width,
                      height: surfaceSize.height,
                      child: _BarragePreview(
                        settings: settings,
                        textOpacity:
                            layout
                                .where((item) => item.key == 'Chat')
                                .map((item) => item.textOpacity)
                                .firstOrNull ??
                            chatTextOpacity,
                        onSelected: selectionOnly && onSelected != null
                            ? () => onSelected!('chat')
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            if (visible.showCrosshair)
              Center(
                child: Semantics(
                  container: true,
                  label: AppStrings.of(context)
                      .text('overlay.workspace.group.crosshair'),
                  button: onSelected != null,
                  image: onSelected == null,
                  onTap: onSelected == null
                      ? null
                      : () => onSelected!('crosshair'),
                  child: GestureDetector(
                    excludeFromSemantics: true,
                    onTap: onSelected == null
                        ? null
                        : () => onSelected!('crosshair'),
                    behavior: HitTestBehavior.opaque,
                    child: Opacity(
                      opacity: (settings['crosshairOpacity']! as num)
                          .toDouble(),
                      child: CustomPaint(
                        key: const Key('overlay-runtime-preview-crosshair'),
                        size: Size.square(size * scale),
                        painter: OverlayCrosshairPainter(settings),
                      ),
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
                    (visorEvents?.height ??
                        OverlayWorkspaceLayoutGeometry
                            .singleEventNotificationPreviewHeight) *
                    scale,
                child: _leaning(
                  eventsTilt,
                  tiltDegrees,
                  OverlayVisorProjection.distance(settings),
                  eventRect,
                  scale,
                  surfaceSize,
                  OverlayEventNotificationPreview(
                    settings: settings,
                    eventRect: eventRect,
                    visorPlacement: visorEvents != null,
                    tiltRight: eventsTilt,
                    tiltDegrees: tiltDegrees,
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
              ),
          ],
        );
      },
    );
  }

  /// The events block through the visor's camera when the visor tilts it.
  static Widget _leaning(
    bool? right,
    double degrees,
    double distance,
    Rect box,
    double scale,
    Size surface,
    Widget child,
  ) => right == null || degrees == 0
      ? child
      : Transform(
          transform: OverlayVisorProjection.forWidget(
            box,
            right: right,
            degrees: degrees,
            surface: surface,
            distance: distance,
            scaleX: scale,
            scaleY: scale,
          ),
          child: child,
        );
}

class _BarragePreview extends StatelessWidget {
  const _BarragePreview({
    required this.settings,
    required this.textOpacity,
    this.onSelected,
  });

  final OverlayWorkspaceSettings settings;
  final double textOpacity;
  final VoidCallback? onSelected;

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
            final senderName = showSender
                ? strings.text('overlay.sample.sender')
                : strings.text('overlay.sample.communicationMessage');
            final sourceLabel = OverlayPreviewSourceScope.of(
              context,
              'Chat',
            )?.labelId;
            final sender = sourceLabel == null
                ? senderName
                : '[${OverlayPreviewSourceScope.label(context, sourceLabel)}] $senderName';
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
                _measureTextWidth(
                  sender,
                  DefaultTextStyle.of(context).style.merge(senderStyle),
                  direction,
                  scaler,
                ) +
                9 +
                _measureTextWidth(
                  sample.$1,
                  DefaultTextStyle.of(context).style.merge(messageStyle),
                  direction,
                  scaler,
                ) +
                (showTime
                    ? 9 +
                          _measureTextWidth(
                            sample.$2,
                            DefaultTextStyle.of(context).style.merge(timeStyle),
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
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSelected,
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
    final width = painter.width;
    painter.dispose();
    return width;
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
