import 'package:flutter/material.dart';

/// 更新海报用到的颜色。主图一直是深色实景，这些颜色不跟深浅色和节日变。
abstract final class UpdatePosterPalette {
  static const imageFallback = Color(0xFF0D151B);
  static const headline = Color(0xFFFFFFFF);
  static const subline = Color(0xFFE3E9ED);

  // 主图上下压暗，保证字看得清。
  static const scrimTop = Color(0x73050709);
  static const scrimClear = Color(0x00050709);
  static const scrimBottom = Color(0xE0050709);

  static const chipFill = Color(0xB8060A0E);
  static const chipText = Color(0xFFE7EEF2);

  // 交易的蓝色不跟节日走，所以不用主色。
  static const tradeArtDark = Color(0xFF173348);
  static const tradeArtLight = Color(0xFFE1EDF7);
}
