import 'package:flutter/material.dart';

import '../runtime/test_build_notice_copy.dart';
import 'cig_fankit_notice.dart';

/// The terms and notices themselves, shown once to accept and any time to read.
/// [license] is the caller's view of the full client license.
class UsageTermsSections extends StatelessWidget {
  const UsageTermsSections({required this.license, super.key});
  final Widget license;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    String t(String cn, String tw, String en) => locale.languageCode == 'en'
        ? en
        : locale.scriptCode == 'Hant' ||
              const {'TW', 'HK', 'MO'}.contains(locale.countryCode)
        ? tw
        : cn;
    Widget heading(String cn, String tw, String en) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(
          t(cn, tw, en),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading('使用风险与非官方声明', '使用風險與非官方聲明', 'Risks and unofficial status'),
        Text(testBuildNoticeBody(locale)),
        heading('数据与可选功能', '資料與可選功能', 'Data and optional features'),
        Text(
          t(
            '登录、消息及其他联网功能需要连接相应服务。同意本页条款不会自动开启游玩时长统计、地点代码贡献或在线共享；这些选择仍在对应设置中单独确认。',
            '登入、訊息及其他連線功能需要連接相應服務。同意本頁條款不會自動開啟遊玩時長統計、地點代碼貢獻或線上分享；這些選擇仍在對應設定中單獨確認。',
            'Sign-in, messaging and other online features connect to their services. Accepting these terms does not enable play-time recording, location-code contributions or online sharing. Those choices remain separate.',
          ),
        ),
        heading('游戏素材权利声明', '遊戲素材權利聲明', 'Game content rights'),
        const Text(CigFankitLegalNotice.requiredEnglish),
        heading('完整客户端许可', '完整用戶端授權條款', 'Full client license'),
        license,
      ],
    );
  }
}
