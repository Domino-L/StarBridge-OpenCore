import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';

import '../../features/friends/social_layout_test.dart' show app, size;

void main() {
  testWidgets('navigating to friend resets sidebar search and unread filter', (
    tester,
  ) async {
    size(tester, const Size(1200, 800));
    Widget subject(String? selected) => app(
      MenuCommsPanel(
        view: MenuCommsView(
          'ready',
          name: selected == null ? null : 'Friend',
          profileKey: selected,
          rows: [
            (
              key: 'c1',
              name: 'Friend',
              time: DateTime(2026),
              unread: 0,
              request: false,
            ),
          ],
        ),
        onClose: () {},
        onAction: (_, _) {},
      ),
    );
    await tester.pumpWidget(subject(null));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'not-matching');
    await tester.tap(find.text('未读'));
    await tester.pump();
    expect(find.byKey(const ValueKey('menu-conversation-c1')), findsNothing);
    await tester.pumpWidget(subject('c1'));
    await tester.pump();
    expect(find.byKey(const ValueKey('menu-conversation-c1')), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
      '',
    );
    expect(tester.takeException(), isNull);
  });
}
