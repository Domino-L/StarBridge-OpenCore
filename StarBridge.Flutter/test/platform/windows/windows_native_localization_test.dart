import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows runner compiles native localized strings as UTF-8', () {
    final runnerCmake = File('windows/runner/CMakeLists.txt')
        .readAsStringSync();
    final lifecycleSource = File(
      'windows/runner/application_lifecycle_bridge.cpp',
    ).readAsStringSync();

    expect(
      runnerCmake,
      contains(r'target_compile_options(${BINARY_NAME} PRIVATE /utf-8)'),
      reason:
          'MSVC otherwise decodes UTF-8 C++ source through the active Windows '
          'code page and corrupts Chinese tray and notification text.',
    );
    expect(lifecycleSource, contains('星海舰桥仍在运行'));
    expect(lifecycleSource, contains('打开星海舰桥'));
    expect(lifecycleSource, contains('完全退出'));
    expect(lifecycleSource, contains('Shell_NotifyIconW'));
    expect(lifecycleSource, contains('AppendMenuW'));
  });
}
