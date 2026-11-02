import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_chat_archive.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_history.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';

import '../../app/menu_overlay/menu_comms_session_test.dart' show Port, peer;
import '../../app/menu_overlay/menu_chat_continuity_test.dart' show Archive;
import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3cj_test.dart' show act, callback;

class HeldArchive extends Archive implements MenuChatArchive {
  final targets = <(String, String)>[];
  final pending = Completer<void>();
  @override
  Future<void> clear(String kind, String reference) async {
    targets.add((kind, reference));
    await pending.future;
  }
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final outcome in ['accepted', 'late-failure']) {
      testWidgets(
        '$suite actual primary archive $outcome never uses A decision on B',
        (t) async {
          size(t, const Size(900, 900));
          final port = Port(),
              archive = HeldArchive(),
              view = ValueNotifier(const MenuCommsView('idle'));
          final session = MenuCommsSession(
            port,
            (raw) => view.value = MenuCommsView.parse(jsonEncode(raw)),
            archive: archive,
          )..show(true);
          try {
            port.directories.single.complete([peer('A'), peer('B')]);
            await t.pump();
            final targets = view.value.rows;
            session.act('select', targets.first.key);
            await t.pump();
            await t.pump();
            await t.pumpWidget(
              scopedApp(
                ValueListenableBuilder<MenuCommsView>(
                  valueListenable: view,
                  builder: (_, v, _) => MenuCommsHistory(
                    view: v,
                    active: false,
                    onAction: session.act,
                  ),
                ),
                suite,
              ),
            );
            await frames(t);
            await act(t, 'pointer', '清除本机记录');
            final stale = callback(t, '确认清除本机记录');
            session.act('select', targets.last.key);
            await t.pump();
            await t.pump();
            await frames(t);
            expect(find.text('确认清除本机记录'), findsNothing);
            stale();
            expect(archive.targets, isEmpty);
            await act(t, 'pointer', '清除本机记录');
            await act(t, 'pointer', '确认清除本机记录');
            expect(archive.targets, [('private', 'secret-B')]);
            expect(view.value.notice, isNot(contains('已清除')));
            stale();
            expect(archive.targets, hasLength(1));
            if (outcome == 'late-failure') {
              session.act('select', targets.first.key);
              await t.pump();
              await t.pump();
              archive.pending.completeError(
                StateError('synthetic archive failure'),
              );
              await frames(t);
              expect(view.value.name, 'A');
              expect(view.value.notice, isNot(contains('未能清除')));
            } else {
              archive.pending.complete();
              await frames(t);
              expect(view.value.notice, contains('已清除'));
            }
            expect(port.sends + port.receipts, 0);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            await frames(t);
            session.dispose();
            if (!archive.pending.isCompleted) archive.pending.complete();
            await t.pump(const Duration(seconds: 13));
            view.dispose();
          }
        },
      );
    }
    for (final location in ['before', 'rows', 'after']) {
      testWidgets(
        '$suite actual generic $location template renews grants without transferring confirmation',
        (t) async {
          final revision = ValueNotifier(1), calls = <(String, String)>[];
          MenuFeatureView projection(int n) => MenuFeatureView.parse({
            'state': 'ready',
            'scope': 's1',
            'title': '功能',
            'buttons': location == 'rows'
                ? []
                : [
                    {
                      'key': 'a$n',
                      'label': '操作',
                      'input': '输入',
                      'limit': 16,
                      'confirm': '确认这个操作？',
                    },
                  ],
            'rows': location == 'rows'
                ? [
                    {
                      'title': '同名对象',
                      'detail': '说明',
                      'buttons': [
                        {
                          'key': 'a$n',
                          'label': '操作',
                          'limit': 16,
                          'confirm': '确认这个操作？',
                        },
                      ],
                    },
                  ]
                : [],
          });
          await t.pumpWidget(
            scopedApp(
              ValueListenableBuilder<int>(
                valueListenable: revision,
                builder: (_, n, _) => MenuFeaturePanel(
                  view: projection(n),
                  actionsAfterRows: location == 'after',
                  onAction: (a, v) => calls.add((a, v)),
                ),
              ),
              suite,
            ),
          );
          await frames(t);
          if (location != 'rows') {
            await t.enterText(find.byType(TextField), 'draft');
          }
          await act(t, 'pointer', '操作');
          final stale = callback(t, '确认操作');
          revision.value = 2;
          await t.pump();
          await t.pump();
          expect(find.text('确认操作'), findsNothing);
          stale();
          expect(calls, isEmpty);
          if (location != 'rows') {
            expect(
              t.widget<TextField>(find.byType(TextField)).controller!.text,
              'draft',
            );
          }
          await act(t, 'pointer', '操作');
          await act(t, 'pointer', '确认操作');
          expect(calls, [('a2', location == 'rows' ? '' : 'draft')]);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await frames(t);
          revision.dispose();
        },
      );
    }
  }
}
