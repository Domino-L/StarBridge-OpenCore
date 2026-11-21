import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/gameplay_time/gameplay_identity_notice.dart';
import 'package:starbridge_flutter/features/gameplay_time/gameplay_time_panel.dart';

import 'gameplay_time_test.dart' show Harness, app;

void main() {
  const languages = [
    (
      Locale('zh', 'CN'),
      '暂时连不上服务器，时长照常记录，账号累计稍后显示。',
      '连不上服务器已超过 30 分钟，时长暂停记录，连上后自动继续。已保存的时长不受影响。',
      '游戏身份还没核对上',
      '（稍后更新）',
    ),
    (
      Locale('zh', 'TW'),
      '暫時連不上伺服器，時長照常記錄，帳號累計稍後顯示。',
      '連不上伺服器已超過 30 分鐘，時長暫停記錄，連上後自動繼續。已儲存的時長不受影響。',
      '遊戲身分還沒核對上',
      '（稍後更新）',
    ),
    (
      Locale('en'),
      "Can't reach the server right now. Playtime is still being recorded; the account total will show later.",
      "Couldn't reach the server for over 30 minutes. Playtime recording is paused and resumes automatically once connected. Saved playtime is not affected.",
      'Your game identity is not matched yet',
      ' (updates later)',
    ),
  ];
  for (final (locale, connection, paused, identity, suffix) in languages) {
    for (final reason in ['connection', 'connectionPaused', 'identity', null]) {
      testWidgets('$locale pauseReason=$reason preserves the right notice', (
        tester,
      ) async {
        final h = Harness(historySupported: false)
          ..error = reason == 'connection' ? null : 'gameplay.account_changed'
          ..pauseReason = reason
          ..accountTotalStale = reason == 'connection' || reason == 'connectionPaused'
          ..seconds = 623 * 3600 + 300
          ..accountTotalState = 'available'
          ..accountTotalSeconds = 900 * 3600;
        await tester.pumpWidget(app(
          GameplayTimePanel(controller: h.controller, onConfirmIdentity: (_) async {}),
          locale: locale,
        ));
        await tester.pumpAndSettle();
        final isConnection = reason == 'connection' || reason == 'connectionPaused';
        if (isConnection) {
          expect(find.text(reason == 'connection' ? connection : paused), findsOneWidget);
          expect(find.textContaining(identity), findsNothing);
          expect(find.textContaining(suffix), findsOneWidget);
          expect(find.byKey(const Key('gameplay-time-confirm-identity')), findsNothing);
        } else {
          expect(find.textContaining(identity), findsOneWidget,
              reason: 'A missing field must keep the old Host identity notice.');
          expect(find.byKey(const Key('gameplay-time-confirm-identity')), findsOneWidget);
        }
        final total = tester.widget<Text>(find.byKey(const Key('gameplay-time-total')));
        expect(total.data, contains('623'));
        expect(h.controller.value.seconds, 623 * 3600 + 300);
        expect(h.controller.value.pauseReason, reason);
        expect(h.controller.value.recording, reason == 'connection');
        // The controller maps the wire code gameplay.account_changed to identityUnconfirmed.
        expect(h.controller.value.error, reason == 'connection' ? isNull : 'identityUnconfirmed');
        await tester.pumpWidget(app(
          GameplayIdentityNotice(controller: h.controller, onConfirmIdentity: (_) async {}),
          locale: locale,
        ));
        await tester.pumpAndSettle();
        expect(isConnection ? find.text(reason == 'connection' ? connection : paused)
            : find.textContaining(identity), findsOneWidget);
        expect(find.byKey(const Key('gameplay-identity-notice-confirm')),
            isConnection ? findsNothing : findsOneWidget);
        await h.close(tester);
        await tester.pump();
      });
    }
  }
  testWidgets('no previously read account total keeps the unavailable label', (tester) async {
    final h = Harness(historySupported: false)
      ..error = null
      ..pauseReason = 'connection'
      ..accountTotalStale = true
      ..seconds = 623 * 3600;
    await tester.pumpWidget(app(GameplayTimePanel(controller: h.controller)));
    await tester.pumpAndSettle();
    expect(find.textContaining('账号累计暂时读不到'), findsOneWidget);
    expect(find.textContaining('（稍后更新）'), findsNothing);
    await h.close(tester);
    await tester.pump();
  });
}
