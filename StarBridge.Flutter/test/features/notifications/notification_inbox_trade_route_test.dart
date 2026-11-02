// SCM station messages in the notification center (CX-04) open 我的交易 and
// 交易消息; the shell hands the `section` to the destination.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_page.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';

import '../../design_system/interaction/interaction_batch3dl_test.dart'
    show Inbox, notice;
import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;
import '../friends/social_layout_test.dart' show size;

void main() {
  testWidgets('trade and trade-chat notices open their sections', (t) async {
    size(t, const Size(1100, 950));
    final inbox = Inbox()
      ..items = [
        notice('trade', 'marketplace_trade'),
        notice('chat', 'marketplace_chat'),
      ];
    addTearDown(inbox.dispose);
    await t.pumpWidget(
      scopedApp(
        NativeViewportScope(
          active: false,
          child: Actions(
            actions: {
              OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
                onInvoke: (intent) {
                  inbox.order.add(intent.route);
                  return null;
                },
              ),
            },
            child: NotificationInboxPage(controller: inbox),
          ),
        ),
        InteractionSuite.standard,
      ),
    );
    await t.pumpAndSettle();
    for (final ref in ['trade', 'chat']) {
      await t.tap(find.byKey(ValueKey(('notification-destination', ref))));
      await t.pumpAndSettle();
    }
    expect(inbox.order, [
      'read',
      '/marketplace?section=trades',
      'read',
      '/messages?section=trade',
    ]);
    await t.pumpWidget(const SizedBox());
  });
}
