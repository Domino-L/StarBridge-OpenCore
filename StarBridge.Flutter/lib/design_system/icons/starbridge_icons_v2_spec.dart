import 'package:flutter/foundation.dart';

import 'starbridge_icons_v2_pen.dart';

typedef IconPaint = void Function(IconPen g);

@immutable
final class IconSpec {
  const IconSpec(
    this.key,
    this.zh,
    this.group,
    this.replaces,
    this.paint, {
    this.note,
  });
  final String key;
  final String zh;
  final String group;

  /// Legacy references this glyph replaces: SB.* (StarBridgeIconSemantic),
  /// Std.* (StandardIconSemantic), Menu.* (MenuGlyph), Window.* (caption).
  final List<String> replaces;
  final IconPaint paint;
  final String? note;
}

const iconGroups = [
  '导航与模块',
  '社交与通讯',
  '组织与权限',
  '游戏与识别',
  '时间与数据',
  '操作',
  '状态与选择',
  '方向与窗口',
];
