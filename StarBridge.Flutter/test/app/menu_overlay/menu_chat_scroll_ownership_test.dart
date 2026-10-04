import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_channel_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';

import '../../features/friends/social_layout_test.dart' show app, size;
import 'menu_comms_channels_test.dart' show channel;

void main() {
  for (final room in [false, true]) {
    testWidgets(
      'embedded ${room ? "room" : "organization"} has one history scroll owner',
      (tester) async {
        size(tester, const Size(660, 440));
        await tester.pumpWidget(
          app(
            MenuChannelPanel(
              view: MenuFeatureView.parse(channel()),
              active: true,
              embeddedOrganization: !room,
              embeddedRoom: room,
              onAction: (_, _) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final history = find.byKey(const ValueKey('menu-channel-history'));
        expect(
          find.ancestor(
            of: history,
            matching: find.byType(SingleChildScrollView),
          ),
          findsNothing,
          reason: 'Message history must not sit inside a second page scroller',
        );
        expect(
          find.byKey(const ValueKey('menu-channel-draft')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('menu-channel-send')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
