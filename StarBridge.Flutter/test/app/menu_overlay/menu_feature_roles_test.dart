import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_room_view.dart';
import 'package:starbridge_flutter/design_system/controls/semantic_action_style.dart';

import '../../features/friends/social_layout_test.dart' show app;

Map<String, Object?> payload([Map<String, Object?> extra = const {}]) => {
  'state': 'ready',
  'buttons': [
    {'key': 'a1', 'label': 'Leave room', 'limit': 128, ...extra},
  ],
};

void main() {
  test('legacy fields default without label inference', () {
    final button = MenuFeatureView.parse(payload()).buttons.single;
    expect(button.role, isNull);
    expect(button.secret, isFalse);
  });
  test('role grammar rejects explicit null and invalid types', () {
    for (final role in [
      null,
      3,
      true,
      '',
      'LeaveRoom',
      'leave-room',
      'a' * 33,
    ]) {
      expect(
        MenuFeatureView.parse(payload({'role': role})).state,
        'unavailable',
      );
    }
    expect(
      MenuFeatureView.parse(payload({'role': 'leaveRoom'})).buttons.single.role,
      'leaveRoom',
    );
  });
  test('secret and selected reject explicit null and non booleans', () {
    for (final invalid in [null, 0, 'true']) {
      expect(
        MenuFeatureView.parse(payload({'secret': invalid})).state,
        'unavailable',
      );
      expect(
        MenuFeatureView.parse({
          'state': 'ready',
          'rows': [
            {'title': 'Alpha', 'selected': invalid},
          ],
        }).state,
        'unavailable',
      );
      expect(MenuFeatureView.parse({'state': 'ready', 'channels': [{'title': 'Alpha', 'selected': invalid}]}).state, 'unavailable');
    }
  });
  test('selected survives image removal', () {
    final view = MenuFeatureView.parse({
      'state': 'ready',
      'channels': [
        {'title': 'Alpha', 'selected': true},
      ],
    });
    expect(view.channels.single.selected, isTrue);
    expect(view.withoutOrganizationImages().channels.single.selected, isTrue);
  });
  testWidgets(
    'secret obscures English inputs independently of displayed words',
    (tester) async {
      for (final secret in [true, false]) {
        final button = MenuFeatureView.parse(
          payload({'input': 'Room code', 'secret': secret, 'role': 'joinRoom'}),
        ).buttons.single;
        await tester.pumpWidget(
          app(
            MenuFeatureAction(
              action: button,
              enabled: true,
              onAction: (_, _) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Leave room').first);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).obscureText,
          secret,
        );
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets(
    'English leave action retains shared warning styling and dispatch',
    (tester) async {
      var sent = '';
      final parsed = MenuFeatureView.parse(payload({'role': 'leaveRoom'}));
      final view = MenuFeatureView(
        'ready',
        buttons: parsed.buttons,
        room: const MenuRoomView('members', '', '', 8, 0, [], false, false),
      );
      await tester.pumpWidget(
        app(MenuRoomsPanel(view: view, onAction: (key, _) => sent = key)),
      );
      await tester.pumpAndSettle();
      final action = tester.widget<MenuFeatureAction>(
        find.byType(MenuFeatureAction).first,
      );
      expect(action.tone, ActionTone.warning);
      await tester.tap(find.text('Leave room').first);
      await tester.pumpAndSettle();
      expect(sent, 'a1');
    },
  );
}
