import 'package:flutter/foundation.dart';

abstract interface class WindowChromePort {
  ValueListenable<bool> get isMaximized;

  Future<void> beginDrag();

  Future<void> minimize();

  Future<void> toggleMaximize();

  Future<void> close();
}
