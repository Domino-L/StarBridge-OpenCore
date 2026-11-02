import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_appearance_preview_status.dart';

void main() {
  test('preview status preserves state precedence and locale selection', () {
    for (final locale in [
      const Locale('en'),
      const Locale('zh'),
      const Locale('zh', 'TW'),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    ]) {
      final english = locale.languageCode != 'zh';
      final traditional =
          locale.scriptCode == 'Hant' || locale.countryCode == 'TW';
      for (var mask = 0; mask < 16; mask++) {
        final closed = mask & 1 != 0, failed = mask & 2 != 0;
        final hasSession = mask & 4 != 0, readOnly = mask & 8 != 0;
        final index = closed
            ? 0
            : failed
            ? 1
            : !hasSession
            ? 2
            : readOnly
            ? 3
            : 4;
        final prefixes = english
            ? [
                'Preview ended.',
                'Preview could not update or exit.',
                'Opening the native overlay',
                'Inspect your current overlay',
                'Your actual layout',
              ]
            : traditional
            ? ['預覽已結束', '預覽未能更新或退出', '正在開啟真實浮層', '查看目前浮層', '使用你的真實配置']
            : ['预览已结束', '预览未能更新或退出', '正在打开真实浮层', '查看当前浮层', '使用你的真实布局'];
        expect(
          overlayAppearancePreviewStatus(
            locale,
            closed: closed,
            failed: failed,
            hasSession: hasSession,
            readOnly: readOnly,
          ),
          startsWith(prefixes[index]),
        );
      }
    }
  });
}
