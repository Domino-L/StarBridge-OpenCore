import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_copy.dart';

void main() {
  const expected = [
    (Locale('zh', 'CN'),
        '机库已保存到你的账号。舰队和组织能看到哪些舰船，仍然按你的共享设置；个人页访客能看到什么，按个人页的公开范围和模块。'),
    (Locale('zh', 'TW'),
        '機庫已儲存到你的帳號。艦隊和組織能看到哪些艦船，仍然依你的分享設定；個人頁訪客能看到什麼，依個人頁的公開範圍和模組。'),
    (Locale('en'),
        "Your hangar is saved to your account. What fleets and organizations can see still follows your sharing settings; what profile visitors can see follows your profile's visibility and modules."),
  ];

  for (final (locale, copy) in expected) {
    testWidgets('first upload copy for $locale', (tester) async {
      await tester.pumpWidget(
        Localizations(
          locale: locale,
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: Builder(
            builder: (context) {
              expect(LocalHangarCopy(context).cloudFirstUpload, copy);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  }
}
