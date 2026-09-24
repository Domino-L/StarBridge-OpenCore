import 'package:flutter/foundation.dart';

@immutable
final class OverlayWorkspaceLayoutItem {
  const OverlayWorkspaceLayoutItem({
    required this.key,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.horizontalAnchor,
    required this.verticalAnchor,
    required this.isLocked,
    required this.textOpacity,
    required this.backgroundOpacity,
    this.decorationOpacity = 1,
  });

  final String key;
  final double x;
  final double y;
  final double width;
  final double height;
  final String horizontalAnchor;
  final String verticalAnchor;
  final bool isLocked;
  final double textOpacity;
  final double backgroundOpacity;
  final double decorationOpacity;

  factory OverlayWorkspaceLayoutItem.fromMap(Map<String, Object?> source) {
    const requiredFields = <String>{
      'key',
      'x',
      'y',
      'width',
      'height',
      'horizontalAnchor',
      'verticalAnchor',
      'isLocked',
      'textOpacity',
      'backgroundOpacity',
    };
    const allowedFields = <String>{...requiredFields, 'decorationOpacity'};
    if (!source.keys.toSet().containsAll(requiredFields) ||
        source.keys.any((field) => !allowedFields.contains(field))) {
      throw const FormatException('Invalid overlay layout fields.');
    }
    final key = source['key'];
    final x = source['x'];
    final y = source['y'];
    final width = source['width'];
    final height = source['height'];
    final horizontalAnchor = source['horizontalAnchor'];
    final verticalAnchor = source['verticalAnchor'];
    final isLocked = source['isLocked'];
    final textOpacity = source['textOpacity'];
    final backgroundOpacity = source['backgroundOpacity'];
    final decorationOpacity = source['decorationOpacity'] ?? 1.0;
    if (key is! String ||
        key.isEmpty ||
        x is! num ||
        y is! num ||
        width is! num ||
        height is! num ||
        horizontalAnchor is! String ||
        !const {'Left', 'Center', 'Right'}.contains(horizontalAnchor) ||
        verticalAnchor is! String ||
        !const {'Top', 'Middle', 'Bottom'}.contains(verticalAnchor) ||
        isLocked is! bool ||
        textOpacity is! num ||
        backgroundOpacity is! num ||
        decorationOpacity is! num ||
        !x.isFinite ||
        x < 0 ||
        x > 0.95 ||
        !y.isFinite ||
        y < 0 ||
        y > 0.95 ||
        !width.isFinite ||
        width < 0.05 ||
        width > 1 ||
        !height.isFinite ||
        height < 0.05 ||
        height > 1 ||
        !textOpacity.isFinite ||
        textOpacity < 0 ||
        textOpacity > 1 ||
        !backgroundOpacity.isFinite ||
        backgroundOpacity < 0 ||
        backgroundOpacity > 1 ||
        !decorationOpacity.isFinite ||
        decorationOpacity < 0 ||
        decorationOpacity > 1) {
      throw const FormatException('Invalid overlay layout values.');
    }
    return OverlayWorkspaceLayoutItem(
      key: key,
      x: x.toDouble(),
      y: y.toDouble(),
      width: width.toDouble(),
      height: height.toDouble(),
      horizontalAnchor: horizontalAnchor,
      verticalAnchor: verticalAnchor,
      isLocked: isLocked,
      textOpacity: textOpacity.toDouble(),
      backgroundOpacity: backgroundOpacity.toDouble(),
      decorationOpacity: decorationOpacity.toDouble(),
    );
  }

  Map<String, Object?> toMap() => {
    'key': key,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'horizontalAnchor': horizontalAnchor,
    'verticalAnchor': verticalAnchor,
    'isLocked': isLocked,
    'textOpacity': textOpacity,
    'backgroundOpacity': backgroundOpacity,
    'decorationOpacity': decorationOpacity,
  };

  OverlayWorkspaceLayoutItem copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    String? horizontalAnchor,
    String? verticalAnchor,
    bool? isLocked,
    double? textOpacity,
    double? backgroundOpacity,
    double? decorationOpacity,
  }) => OverlayWorkspaceLayoutItem(
    key: key,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    horizontalAnchor: horizontalAnchor ?? this.horizontalAnchor,
    verticalAnchor: verticalAnchor ?? this.verticalAnchor,
    isLocked: isLocked ?? this.isLocked,
    textOpacity: textOpacity ?? this.textOpacity,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    decorationOpacity: decorationOpacity ?? this.decorationOpacity,
  );
}
