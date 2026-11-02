import 'package:flutter/widgets.dart';

String overlayAppearancePreviewStatus(
  Locale locale, {
  required bool closed,
  required bool failed,
  required bool hasSession,
  required bool readOnly,
}) {
  String copy(String cn, String tw, String en) => locale.languageCode != 'zh'
      ? en
      : locale.scriptCode == 'Hant' || locale.countryCode == 'TW'
      ? tw
      : cn;
  if (closed) {
    return copy(
      '预览已结束，请返回外观中心。',
      '預覽已結束，請返回外觀中心。',
      'Preview ended. Return to the appearance center.',
    );
  }
  if (failed) {
    return copy(
      '预览未能更新或退出，可重试退出；草稿仍保留。',
      '預覽未能更新或退出，可重試退出；草稿仍保留。',
      'Preview could not update or exit. Retry exit; your draft is retained.',
    );
  }
  if (!hasSession) {
    return copy('正在打开真实浮层…', '正在開啟真實浮層…', 'Opening the native overlay…');
  }
  if (readOnly) {
    return copy(
      '查看当前浮层 · 不更改设置 · Esc 退出',
      '查看目前浮層 · 不變更設定 · Esc 結束',
      'Inspect your current overlay · Settings stay unchanged · Esc to exit',
    );
  }
  return copy(
    '使用你的真实布局 · 不计解锁时间 · 修改需手动保存 · Esc 退出',
    '使用你的真實配置 · 不計解鎖時間 · 修改需手動儲存 · Esc 退出',
    'Your actual layout · No unlock time · Save edits explicitly · Esc to exit',
  );
}
