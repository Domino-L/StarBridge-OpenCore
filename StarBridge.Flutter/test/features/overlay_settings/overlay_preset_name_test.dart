import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_name.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';

import 'overlay_settings_ux_a_test.dart' show settings;

OverlayWorkspacePreset _preset(String id, String name) =>
    OverlayWorkspacePreset(
      id: id,
      name: name,
      isActive: true,
      storageState: 'saved',
      settings: settings(),
      layout: const [],
    );

void main() {
  final en = AppStrings.resolve(const Locale('en', 'US'));
  final zhCn = AppStrings.resolve(const Locale('zh', 'CN'));
  final zhTw = AppStrings.resolve(const Locale('zh', 'TW'));

  test('the built-in plan is shown in the reader language until renamed', () {
    final builtIn = _preset('preset1', '默认预设');
    expect(builtIn.shownName(en), 'Default profile');
    expect(builtIn.shownName(zhCn), '默认预设');
    expect(builtIn.shownName(zhTw), '預設方案');
    expect(_preset('preset1', '舰桥').shownName(en), '舰桥', reason: 'renamed');
    expect(
      _preset('preset2', '默认预设').shownName(en),
      '默认预设',
      reason: 'only the built-in plan, never a user plan with the same name',
    );
  });

  test('saving the shown built-in name keeps the stored one', () {
    final builtIn = _preset('preset1', '默认预设');
    expect(builtIn.savedName('Default profile', en), '默认预设');
    expect(builtIn.savedName('Combat', en), 'Combat');
    expect(
      _preset('preset2', 'Default profile').savedName('Default profile', en),
      'Default profile',
    );
  });
}
