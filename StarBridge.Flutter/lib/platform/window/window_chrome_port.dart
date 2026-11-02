import 'package:flutter/foundation.dart';

abstract interface class WindowChromePort {
  ValueListenable<bool> get isMaximized;

  Future<void> beginDrag();

  Future<void> minimize();

  Future<void> toggleMaximize();

  Future<void> close();

  /// 运行时换窗口、任务栏、托盘的图标。`default` 是平时的图标。
  /// 桌面快捷方式和安装包的图标不受影响。
  Future<void> setIconVariant(String variant);
}
