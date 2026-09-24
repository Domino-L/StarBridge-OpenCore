import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'overlay_workspace_models.dart';

/// WPF-compatible geometry in logical screen pixels. Inline editing defaults
/// to the reference surface; fullscreen supplies its actual monitor surface.
final class OverlayWorkspaceLayoutGeometry {
  const OverlayWorkspaceLayoutGeometry._();

  static const referenceSize = Size(1920, 1080);
  static const double edgeSnapThreshold = 12;
  static const double horizontalModuleSnapThreshold = 24;
  static const double verticalModuleSnapThreshold = 32;
  static const double eventNotificationEdgeInset = 0;
  static const double eventNotificationVerticalInset = 0;
  static const double singleEventNotificationPlacementHeight = 90;
  static const double singleEventNotificationPreviewHeight = 64;

  // Geometry-only reset matches InformationOverlayDefaults.CreateLayout and
  // WPF ResetSelectedOverlayModule: preserve visibility, opacity and anchors.
  static OverlayWorkspaceLayoutItem resetPosition(
    OverlayWorkspaceLayoutItem item,
    String presetId,
  ) {
    const standard = {
      'Notice': [0.34, 0.0, 0.32, 0.055],
      'Squads': [0.0, 0.4211, 0.1327, 0.1042],
      'Members': [0.0, 0.5253, 0.1327, 0.1557],
      'Chat': [0.0, 0.681, 0.1327, 0.1069],
    };
    const compact = {
      'Notice': [0.34, 0.0, 0.32, 0.055],
      'Squads': [0.01, 0.36, 0.13, 0.24],
      'Members': [0.84, 0.58, 0.15, 0.18],
      'Chat': [0.35, 0.78, 0.30, 0.18],
    };
    const command = {
      'Notice': [0.285, 0.0, 0.43, 0.075],
      'Squads': [0.01, 0.30, 0.18, 0.42],
      'Members': [0.78, 0.54, 0.21, 0.26],
      'Chat': [0.35, 0.75, 0.30, 0.21],
    };
    final values = (switch (presetId) {
      'compact' => compact,
      'command' => command,
      _ => standard,
    })[item.key];
    return values == null
        ? item
        : item.copyWith(
            x: values[0],
            y: values[1],
            width: values[2],
            height: values[3],
          );
  }

  static Rect resolve(
    OverlayWorkspaceLayoutItem item, {
    Size surfaceSize = referenceSize,
  }) {
    final constraints = _constraints(item.key, surfaceSize);
    final width = (item.width * surfaceSize.width).clamp(
      constraints.minWidth,
      constraints.maxWidth,
    );
    final height = (item.height * surfaceSize.height).clamp(
      constraints.minHeight,
      constraints.maxHeight,
    );
    final left = switch (item.horizontalAnchor) {
      'Left' => item.x * surfaceSize.width,
      'Right' =>
        surfaceSize.width -
            ((1 - item.x - item.width) * surfaceSize.width) -
            width,
      _ => ((item.x + item.width / 2) * surfaceSize.width) - width / 2,
    };
    final top = switch (item.verticalAnchor) {
      'Top' => item.y * surfaceSize.height,
      'Bottom' =>
        surfaceSize.height -
            ((1 - item.y - item.height) * surfaceSize.height) -
            height,
      _ => ((item.y + item.height / 2) * surfaceSize.height) - height / 2,
    };
    return _constrainNoticeDock(
      item.key,
      _clamp(Rect.fromLTWH(left, top, width, height), surfaceSize),
      surfaceSize,
    );
  }

  /// Resolves the whole persisted layout using the same responsive collision
  /// rule as the Windows overlay. Only overlap introduced by module minimum
  /// sizes is corrected; deliberate normalized overlap remains unchanged.
  static Map<String, Rect> resolveItems(
    List<OverlayWorkspaceLayoutItem> items, {
    Size surfaceSize = referenceSize,
  }) {
    final unique = <String, OverlayWorkspaceLayoutItem>{};
    for (final item in items) {
      unique.putIfAbsent(item.key.toLowerCase(), () => item);
    }
    final materialized = unique.values.toList(growable: false);
    final intended = <String, Rect>{
      for (final item in materialized)
        item.key: _resolveIntended(item, surfaceSize),
    };
    final effective = <String, Rect>{
      for (final item in materialized)
        item.key: resolve(item, surfaceSize: surfaceSize),
    };
    final verticalOrder = [...materialized]
      ..sort((first, second) {
        final firstRect = intended[first.key]!;
        final secondRect = intended[second.key]!;
        final vertical = firstRect.top.compareTo(secondRect.top);
        return vertical != 0
            ? vertical
            : firstRect.left.compareTo(secondRect.left);
      });

    for (var lowerIndex = 1; lowerIndex < verticalOrder.length; lowerIndex++) {
      final lower = verticalOrder[lowerIndex];
      final lowerIntended = intended[lower.key]!;
      final lowerEffective = effective[lower.key]!;
      var requiredTop = lowerEffective.top;

      for (var upperIndex = 0; upperIndex < lowerIndex; upperIndex++) {
        final upper = verticalOrder[upperIndex];
        final upperIntended = intended[upper.key]!;
        if (upperIntended.bottom > lowerIntended.top + 0.01 ||
            _horizontalOverlapRatio(upperIntended, lowerIntended) < 0.50) {
          continue;
        }

        final upperEffective = effective[upper.key]!;
        if (upperEffective.bottom <= requiredTop + 0.01) continue;
        final intendedGap = (lowerIntended.top - upperIntended.bottom).clamp(
          0.0,
          double.infinity,
        );
        requiredTop = (upperEffective.bottom + intendedGap).clamp(
          requiredTop,
          double.infinity,
        );
      }

      if (requiredTop > lowerEffective.top + 0.01) {
        effective[lower.key] = Rect.fromLTWH(
          lowerEffective.left,
          requiredTop,
          lowerEffective.width,
          lowerEffective.height,
        );
      }
    }

    return effective;
  }

  static Offset scaleDelta(
    Offset delta,
    Size viewportSize, {
    Size surfaceSize = referenceSize,
  }) => Offset(
    delta.dx * surfaceSize.width / viewportSize.width.clamp(1, double.infinity),
    delta.dy *
        surfaceSize.height /
        viewportSize.height.clamp(1, double.infinity),
  );

  static Rect resolveEventNotificationRect({
    required double surfaceWidth,
    required double surfaceHeight,
    required String side,
    required double normalizedY,
    required double preferredHeight,
    double snapSize = 0,
  }) {
    final normalizedWidth = math.max(1.0, surfaceWidth);
    final normalizedHeight = math.max(1.0, surfaceHeight);
    final width = resolveEventNotificationWidth(normalizedWidth);
    final height = preferredHeight
        .clamp(72.0, math.max(72.0, normalizedHeight))
        .toDouble();
    final minTop = eventNotificationVerticalInset;
    final maxTop = math.max(
      minTop,
      normalizedHeight - height - eventNotificationVerticalInset,
    );
    final available = math.max(1.0, maxTop - minTop);
    var top = minTop + available * normalizedY.clamp(0.0, 1.0);
    if (snapSize > 0) top = _roundTo(top, snapSize);
    top = top.clamp(minTop, maxTop);
    final left = side == 'Left'
        ? eventNotificationEdgeInset
        : math.max(
            eventNotificationEdgeInset,
            normalizedWidth - width - eventNotificationEdgeInset,
          );
    return Rect.fromLTWH(left, top, width, height);
  }

  static double resolveEventNotificationWidth(double surfaceWidth) =>
      (math.max(1.0, surfaceWidth) * 0.22).clamp(320.0, 380.0);

  static OverlayWorkspaceLayoutItem move({
    required OverlayWorkspaceLayoutItem item,
    required List<OverlayWorkspaceLayoutItem> layout,
    required Offset delta,
    double snapPixels = 0,
    bool smartSnap = true,
    Size surfaceSize = referenceSize,
  }) {
    var rect = resolve(item, surfaceSize: surfaceSize).shift(delta);
    if (snapPixels > 0) {
      rect = Rect.fromLTWH(
        _roundTo(rect.left, snapPixels),
        _roundTo(rect.top, snapPixels),
        rect.width,
        rect.height,
      );
    }
    if (smartSnap) {
      rect = _snapPositionAxis(
        item,
        layout,
        rect,
        horizontal: true,
        surfaceSize: surfaceSize,
      );
      rect = _snapPositionAxis(
        item,
        layout,
        rect,
        horizontal: false,
        surfaceSize: surfaceSize,
      );
    }
    return apply(item, _clamp(rect, surfaceSize), surfaceSize: surfaceSize);
  }

  static OverlayWorkspaceLayoutItem resize({
    required OverlayWorkspaceLayoutItem item,
    required List<OverlayWorkspaceLayoutItem> layout,
    required Offset delta,
    double snapPixels = 0,
    bool smartSnap = true,
    Size surfaceSize = referenceSize,
  }) {
    final current = resolve(item, surfaceSize: surfaceSize);
    final constraints = _constraints(item.key, surfaceSize);
    var width = (current.width + delta.dx).clamp(
      constraints.minWidth,
      surfaceSize.width - current.left,
    );
    var height = (current.height + delta.dy).clamp(
      constraints.minHeight,
      surfaceSize.height - current.top,
    );
    if (snapPixels > 0) {
      width = _roundTo(width, snapPixels);
      height = _roundTo(height, snapPixels);
    }
    if (smartSnap) {
      if ((surfaceSize.width - (current.left + width)).abs() <=
          edgeSnapThreshold) {
        width = surfaceSize.width - current.left;
      }
      if ((surfaceSize.height - (current.top + height)).abs() <=
          edgeSnapThreshold) {
        height = surfaceSize.height - current.top;
      }
      width = _snapResizeEdge(
        item,
        layout,
        current.left,
        width,
        horizontal: true,
        surfaceSize: surfaceSize,
      );
      height = _snapResizeEdge(
        item,
        layout,
        current.top,
        height,
        horizontal: false,
        surfaceSize: surfaceSize,
      );
    }
    final rect = Rect.fromLTWH(
      current.left,
      current.top,
      width.clamp(constraints.minWidth, surfaceSize.width - current.left),
      height.clamp(constraints.minHeight, surfaceSize.height - current.top),
    );
    return apply(item, _clamp(rect, surfaceSize), surfaceSize: surfaceSize);
  }

  static OverlayWorkspaceLayoutItem nudge(
    OverlayWorkspaceLayoutItem item,
    String property,
    double delta, {
    Size surfaceSize = referenceSize,
  }) {
    final current = resolve(item, surfaceSize: surfaceSize);
    final rect = switch (property) {
      'x' => Rect.fromLTWH(
        current.left + delta,
        current.top,
        current.width,
        current.height,
      ),
      'y' => Rect.fromLTWH(
        current.left,
        current.top + delta,
        current.width,
        current.height,
      ),
      'width' => Rect.fromLTWH(
        current.left,
        current.top,
        current.width + delta,
        current.height,
      ),
      'height' => Rect.fromLTWH(
        current.left,
        current.top,
        current.width,
        current.height + delta,
      ),
      _ => current,
    };
    return apply(item, rect, surfaceSize: surfaceSize);
  }

  static OverlayWorkspaceLayoutItem dockNotice(
    OverlayWorkspaceLayoutItem item,
    String edge, {
    Size surfaceSize = referenceSize,
  }) {
    if (item.key != 'Notice') return item;
    final current = resolve(item, surfaceSize: surfaceSize);
    final bottom = edge == 'Bottom';
    return apply(
      item.copyWith(verticalAnchor: bottom ? 'Bottom' : 'Top'),
      Rect.fromLTWH(
        current.left,
        bottom ? surfaceSize.height - current.height : 0,
        current.width,
        current.height,
      ),
      surfaceSize: surfaceSize,
    );
  }

  static OverlayWorkspaceLayoutItem apply(
    OverlayWorkspaceLayoutItem item,
    Rect rect, {
    Size surfaceSize = referenceSize,
  }) {
    final constraints = _constraints(item.key, surfaceSize);
    final width = rect.width
        .clamp(
          constraints.minWidth,
          constraints.maxWidth.clamp(1, surfaceSize.width),
        )
        .toDouble();
    final height = rect.height
        .clamp(
          constraints.minHeight,
          constraints.maxHeight.clamp(1, surfaceSize.height),
        )
        .toDouble();
    final constrained = _constrainNoticeDock(
      item.key,
      Rect.fromLTWH(
        rect.left.clamp(0, surfaceSize.width - width),
        rect.top.clamp(0, surfaceSize.height - height),
        width,
        height,
      ),
      surfaceSize,
    );
    return item.copyWith(
      x: constrained.left / surfaceSize.width,
      y: constrained.top / surfaceSize.height,
      width: constrained.width / surfaceSize.width,
      height: constrained.height / surfaceSize.height,
      verticalAnchor: item.key == 'Notice'
          ? (constrained.top <= 0.5 ? 'Top' : 'Bottom')
          : item.verticalAnchor,
    );
  }

  static Rect _snapPositionAxis(
    OverlayWorkspaceLayoutItem item,
    List<OverlayWorkspaceLayoutItem> layout,
    Rect rect, {
    required bool horizontal,
    required Size surfaceSize,
  }) {
    final extent = horizontal ? surfaceSize.width : surfaceSize.height;
    final start = horizontal ? rect.left : rect.top;
    final size = horizontal ? rect.width : rect.height;
    final anchor = horizontal
        ? switch (item.horizontalAnchor) {
            'Left' => rect.left,
            'Right' => rect.right,
            _ => rect.center.dx,
          }
        : switch (item.verticalAnchor) {
            'Top' => rect.top,
            'Bottom' => rect.bottom,
            _ => rect.center.dy,
          };
    var bestDistance = double.infinity;
    var bestDelta = 0.0;

    void consider(double current, double target, double threshold) {
      final distance = (target - current).abs();
      if (distance <= threshold && distance < bestDistance) {
        bestDistance = distance;
        bestDelta = target - current;
      }
    }

    consider(start, 0, edgeSnapThreshold);
    consider(start + size, extent, edgeSnapThreshold);
    consider(anchor, extent / 2, edgeSnapThreshold);
    final moduleThreshold = horizontal
        ? horizontalModuleSnapThreshold
        : verticalModuleSnapThreshold;
    for (final other in layout.where(
      (candidate) => candidate.key != item.key,
    )) {
      final target = resolve(other, surfaceSize: surfaceSize);
      final targetStart = horizontal ? target.left : target.top;
      final targetCenter = horizontal ? target.center.dx : target.center.dy;
      final targetEnd = horizontal ? target.right : target.bottom;
      consider(start, targetStart, moduleThreshold);
      consider(start + size, targetEnd, moduleThreshold);
      consider(start, targetEnd, moduleThreshold);
      consider(start + size, targetStart, moduleThreshold);
      consider(anchor, targetCenter, moduleThreshold);
    }
    if (!bestDistance.isFinite) return rect;
    return horizontal
        ? rect.shift(Offset(bestDelta, 0))
        : rect.shift(Offset(0, bestDelta));
  }

  static double _snapResizeEdge(
    OverlayWorkspaceLayoutItem item,
    List<OverlayWorkspaceLayoutItem> layout,
    double start,
    double size, {
    required bool horizontal,
    required Size surfaceSize,
  }) {
    final edge = start + size;
    final threshold = horizontal
        ? horizontalModuleSnapThreshold
        : verticalModuleSnapThreshold;
    var bestDistance = double.infinity;
    var bestTarget = edge;
    for (final other in layout.where(
      (candidate) => candidate.key != item.key,
    )) {
      final target = resolve(other, surfaceSize: surfaceSize);
      final values = horizontal
          ? [target.left, target.center.dx, target.right]
          : [target.top, target.center.dy, target.bottom];
      for (final value in values) {
        final distance = (edge - value).abs();
        if (distance <= threshold && distance < bestDistance) {
          bestDistance = distance;
          bestTarget = value;
        }
      }
    }
    return bestTarget - start;
  }

  static Rect _clamp(Rect rect, Size surfaceSize) {
    final width = rect.width.clamp(1.0, surfaceSize.width);
    final height = rect.height.clamp(1.0, surfaceSize.height);
    return Rect.fromLTWH(
      rect.left.clamp(0, surfaceSize.width - width),
      rect.top.clamp(0, surfaceSize.height - height),
      width,
      height,
    );
  }

  static Rect _constrainNoticeDock(String key, Rect rect, Size surfaceSize) {
    final clamped = _clamp(rect, surfaceSize);
    if (key != 'Notice') return clamped;
    final bottom = clamped.center.dy >= surfaceSize.height / 2;
    return Rect.fromLTWH(
      clamped.left,
      bottom ? surfaceSize.height - clamped.height : 0,
      clamped.width,
      clamped.height,
    );
  }

  static double _roundTo(double value, double step) =>
      (value / step).round() * step;

  static Rect _resolveIntended(
    OverlayWorkspaceLayoutItem item,
    Size surfaceSize,
  ) {
    final width = item.width.clamp(0.01, 1) * surfaceSize.width;
    final height = item.height.clamp(0.01, 1) * surfaceSize.height;
    final left = switch (item.horizontalAnchor) {
      'Left' => item.x * surfaceSize.width,
      'Right' =>
        surfaceSize.width -
            ((1 - item.x - item.width) * surfaceSize.width) -
            width,
      _ => ((item.x + item.width / 2) * surfaceSize.width) - width / 2,
    };
    final top = switch (item.verticalAnchor) {
      'Top' => item.y * surfaceSize.height,
      'Bottom' =>
        surfaceSize.height -
            ((1 - item.y - item.height) * surfaceSize.height) -
            height,
      _ => ((item.y + item.height / 2) * surfaceSize.height) - height / 2,
    };
    return Rect.fromLTWH(left, top, width, height);
  }

  static double _horizontalOverlapRatio(Rect first, Rect second) {
    final overlap = math.max(
      0.0,
      math.min(first.right, second.right) - math.max(first.left, second.left),
    );
    return overlap / math.max(1.0, math.min(first.width, second.width));
  }

  static _ModuleConstraints _constraints(String key, Size surfaceSize) {
    final wide = surfaceSize.aspectRatio >= 2.1;
    final raw = switch (key) {
      'Notice' => _ModuleConstraints(420, wide ? 1040 : 1120, 52, 118),
      'Squads' => _ModuleConstraints(240, wide ? 460 : 540, 150, 620),
      'Members' => _ModuleConstraints(240, wide ? 480 : 520, 140, 440),
      'Chat' => _ModuleConstraints(240, wide ? 760 : 680, 104, 440),
      _ => _ModuleConstraints(80, surfaceSize.width, 50, surfaceSize.height),
    };
    final width = raw.maxWidth
        .clamp(1.0, math.max(1.0, surfaceSize.width))
        .toDouble();
    final height = raw.maxHeight
        .clamp(1.0, math.max(1.0, surfaceSize.height))
        .toDouble();
    return _ModuleConstraints(
      raw.minWidth.clamp(1.0, width).toDouble(),
      width,
      raw.minHeight.clamp(1.0, height).toDouble(),
      height,
    );
  }
}

final class _ModuleConstraints {
  const _ModuleConstraints(
    this.minWidth,
    this.maxWidth,
    this.minHeight,
    this.maxHeight,
  );

  final double minWidth;
  final double maxWidth;
  final double minHeight;
  final double maxHeight;
}
