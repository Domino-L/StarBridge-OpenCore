import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_channel_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';
import 'package:starbridge_flutter/features/party_rooms/room_feedback.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';

import '../../app/menu_overlay/menu_room_settings_test.dart' show SettingsPort;
import '../../app/menu_overlay/menu_rooms_panel_test.dart' show Chat;
import '../../app/menu_overlay/menu_comms_channels_test.dart' show channel;
import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3cj_test.dart' show act, callback, control;

class HeldRoomPort extends SettingsPort implements RoomChatProvider {
  @override
  final roomChat = Chat();
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final result in ['left', 'unknown']) {
        testWidgets(
          '$suite actual room leave $source $result keeps primary result ownership',
          (t) async {
            size(t, const Size(1000, 1000));
            final semantics = t.ensureSemantics();
            final port = HeldRoomPort()
              ..pendingResult = Completer<RoomCommandResult>();
            final view = ValueNotifier(
              MenuFeatureView.parse({'state': 'idle'}),
            );
            final session = MenuRoomsSession(
              port,
              (raw) => view.value = MenuFeatureView.parse(raw),
            )..show(true);
            try {
              await t.pump();
              expect(view.value.room, isNotNull);
              await t.pumpWidget(
                scopedApp(
                  ValueListenableBuilder<MenuFeatureView>(
                    valueListenable: view,
                    builder: (_, v, _) => MenuRoomsPanel(
                      view: v,
                      active: false,
                      onAction: session.act,
                    ),
                  ),
                  suite,
                ),
              );
              await frames(t);
              final leave = t.widget<StarBridgeActionButton>(control('退出房间'));
              expect(
                leave.tone,
                roomLeaveTone(
                  view.value.room!.presentation(
                    view.value.title,
                    view.value.scope,
                  ),
                ),
              );
              expect(t.getSize(control('退出房间')).width, lessThan(200));
              await act(t, source, '退出房间');
              expect(port.calls, isEmpty);
              final old = callback(t, '确认退出房间');
              await act(t, source, '取消');
              old();
              expect(port.calls, isEmpty);
              await act(t, source, '退出房间');
              await act(t, source, '确认退出房间');
              expect(port.calls, hasLength(1));
              expect(port.calls.single.operation, RoomOperation.leave);
              expect(port.calls.single.data, {'roomId': 'private-room'});
              expect(view.value.notice, isNot(contains('已退出房间')));
              old();
              expect(port.calls, hasLength(1));
              // The fake read follows the server membership result. A successful
              // leave returns to discovery; it need not retain a success toast.
              if (result == 'left') port.joined = false;
              port.pendingResult!.complete(RoomCommandResult(result));
              await frames(t);
              if (result == 'left') {
                expect(view.value.room, isNull);
                expect(view.value.lobby, isNotNull);
              } else {
                expect(view.value.notice, contains('结果未确认'));
              }
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox());
              session.dispose();
              if (!port.pendingResult!.isCompleted) {
                port.pendingResult!.complete(
                  const RoomCommandResult('unknown'),
                );
              }
              await t.pump(const Duration(seconds: 13));
              view.dispose();
              semantics.dispose();
            }
          },
        );
      }
    }
    testWidgets(
      '$suite actual channel retains disabled decision through loading then invalidates on grant and context',
      (t) async {
        size(t, const Size(900, 1000));
        final revision = ValueNotifier(1), calls = <(String, String)>[];
        MenuFeatureView projection(int n) => MenuFeatureView.parse(
          n == 2
              ? {'state': 'loading', 'scope': 's1'}
              : {
                  ...channel(scope: n == 4 ? 's2' : 's1'),
                  'buttons': [
                    {
                      'key': 'a1',
                      'label': '发送消息',
                      'role': 'sendMessage',
                      'limit': 1000,
                    },
                    {
                      'key': n < 3 ? 'a3' : 'a4',
                      'label': '清除本机记录',
                      'role': 'clearLocalHistory',
                      'limit': 128,
                      'confirm': '仅清除当前会话本机记录？',
                    },
                  ],
                },
        );
        try {
          await t.pumpWidget(
            scopedApp(
              ValueListenableBuilder<int>(
                valueListenable: revision,
                builder: (_, n, _) => MenuChannelPanel(
                  view: projection(n),
                  active: false,
                  onAction: (a, v) => calls.add((a, v)),
                ),
              ),
              suite,
            ),
          );
          await frames(t);
          await act(t, 'pointer', '清除本机记录');
          final stale = callback(t, '确认清除本机记录');
          revision.value = 2;
          await frames(t);
          expect(control('确认清除本机记录'), findsOneWidget);
          stale();
          expect(calls, isEmpty);
          await act(t, 'pointer', '取消');
          expect(control('确认清除本机记录'), findsNothing);
          revision.value = 3;
          await frames(t);
          await act(t, 'pointer', '清除本机记录');
          final newer = callback(t, '确认清除本机记录');
          stale();
          expect(calls, isEmpty);
          revision.value = 4;
          await frames(t);
          newer();
          expect(calls, isEmpty);
          expect(control('确认清除本机记录'), findsNothing);
          await act(t, 'pointer', '清除本机记录');
          await act(t, 'pointer', '确认清除本机记录');
          expect(calls, [('a4', '')]);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          await frames(t);
          revision.dispose();
        }
      },
    );
  }
}
