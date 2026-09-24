import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'icon_semantic.dart';
import 'starbridge_icon_geometry.dart';
import 'starbridge_identity_icon_geometry.dart';
import 'starbridge_profile_icon_geometry.dart';
import 'starbridge_system_icon_geometry.dart';

final class StarBridgeIconPainter extends CustomPainter {
  const StarBridgeIconPainter({
    required this.semantic,
    required this.color,
    required this.opticalSize,
    required this.mirrored,
  });

  final StarBridgeIconSemantic semantic;
  final Color color;
  final StarBridgeIconOpticalSize opticalSize;
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    final extent = math.min(size.width, size.height);
    final scale = extent / 24;
    canvas.save();
    canvas.translate((size.width - extent) / 2, (size.height - extent) / 2);
    canvas.scale(scale);
    if (mirrored) {
      canvas.translate(24, 0);
      canvas.scale(-1, 1);
    }

    final geometry = StarBridgeIconCanvas(canvas, color, opticalSize);
    final painted =
        StarBridgeIdentityIconGeometry.paint(semantic, geometry) ||
        StarBridgeProfileIconGeometry.paint(semantic, geometry) ||
        StarBridgeSystemIconGeometry.paint(semantic, geometry);
    assert(painted, 'No StarBridge geometry registered for $semantic.');
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant StarBridgeIconPainter oldDelegate) =>
      semantic != oldDelegate.semantic ||
      color != oldDelegate.color ||
      opticalSize != oldDelegate.opticalSize ||
      mirrored != oldDelegate.mirrored;
}
