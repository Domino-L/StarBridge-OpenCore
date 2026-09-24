import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/shell/shell_layout_mode.dart';

void main() {
  test('navigation adapts across icon, compact, and wide window widths', () {
    expect(ShellLayoutResolver.resolve(900), ShellLayoutMode.iconOnly);
    expect(ShellLayoutResolver.resolve(1039), ShellLayoutMode.iconOnly);
    expect(ShellLayoutResolver.resolve(1040), ShellLayoutMode.compact);
    expect(ShellLayoutResolver.resolve(1259), ShellLayoutMode.compact);
    expect(ShellLayoutResolver.resolve(1260), ShellLayoutMode.wide);
  });
}
