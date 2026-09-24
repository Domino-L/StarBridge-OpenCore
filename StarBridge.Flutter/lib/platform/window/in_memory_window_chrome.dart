import 'package:flutter/foundation.dart';

import 'window_chrome_port.dart';

final class InMemoryWindowChrome implements WindowChromePort {
  final List<String> commands = <String>[];
  final ValueNotifier<bool> _isMaximized = ValueNotifier(false);

  @override
  ValueListenable<bool> get isMaximized => _isMaximized;

  @override
  Future<void> beginDrag() async => commands.add('beginDrag');

  @override
  Future<void> close() async => commands.add('close');

  @override
  Future<void> minimize() async => commands.add('minimize');

  @override
  Future<void> toggleMaximize() async {
    commands.add('toggleMaximize');
    _isMaximized.value = !_isMaximized.value;
  }

  void setMaximizedForTest(bool value) {
    _isMaximized.value = value;
  }
}
