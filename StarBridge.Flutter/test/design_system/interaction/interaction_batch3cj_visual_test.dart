import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3ca_visual_test.dart' show viewport;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3cj_test.dart' show act, callback, control;
import 'interaction_batch3cj_provider_test.dart' show HeldRoomPort;

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  expect(t.takeException(), isNull);
  final image = (await t.runAsync(
    () => (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
        .toImage(),
  ))!;
  try {
    final bytes = (await t.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    final file = File('build/reviews/interaction-batch3cj/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  } finally {
    image.dispose();
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final config in [(430.0, 1.0), (1100.0, 1.0), (430.0, 2.0)]) {
      for (final outlined in [false, true]) {
        testWidgets(
          '$suite $config outlined=$outlined native editor and inline decision review',
          (t) async {
            viewport(t, config);
            final boundary = GlobalKey(), enabled = ValueNotifier(true);
            final old = debugDisableShadows, calls = <(String, String)>[];
            debugDisableShadows = false;
            final name =
                '${suite.name}-${config.$1.toInt()}-${config.$2}-${outlined ? 'outline' : 'plain'}';
            try {
              await t.pumpWidget(
                RepaintBoundary(
                  key: boundary,
                  child: scopedApp(
                    Center(
                      child: SizedBox(
                        width: 340,
                        child: SingleChildScrollView(
                          child: ValueListenableBuilder<bool>(
                            valueListenable: enabled,
                            builder: (_, available, _) => MenuFeatureAction(
                              identity: 's1',
                              action: (
                                key: 'a1',
                                label: '加入房间',
                                confirm: '加入远航者的探索房间？需要审核时将先提交申请。',
                                input: '房间密码',
                                role: 'joinRoom',
                                secret: true,
                                limit: 128,
                              ),
                              enabled: available,
                              outlined: outlined,
                              onAction: (a, v) => calls.add((a, v)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    suite,
                    light: config.$1 > 1000,
                  ),
                ),
              );
              await frames(t);
              await capture(t, boundary, '$name-ready');
              await t.tap(find.byType(TextField));
              await t.pump();
              await t.pump(const Duration(milliseconds: 90));
              await t.enterText(find.byType(TextField), 'draft');
              await capture(t, boundary, '$name-field-focus');
              final initial = t.getRect(control('加入房间'));
              expect(initial.width, lessThanOrEqualTo(340));
              expect(initial.height, lessThan(100));
              final gesture = await t.startGesture(initial.center);
              await t.pump();
              await t.pump(const Duration(milliseconds: 55));
              await capture(t, boundary, '$name-press');
              await gesture.up();
              await t.pump();
              await t.pump(const Duration(milliseconds: 70));
              await capture(t, boundary, '$name-released-confirm');
              await frames(t);
              expect(control('确认加入房间'), findsOneWidget);
              expect(calls, isEmpty);
              await capture(t, boundary, '$name-confirm');
              final stale = callback(t, '确认加入房间');
              enabled.value = false;
              await frames(t);
              stale();
              expect(calls, isEmpty);
              await capture(t, boundary, '$name-disabled-cancel');
              await act(t, 'keyboard', '取消');
              expect(control('确认加入房间'), findsNothing);
              enabled.value = true;
              await frames(t);
              await act(t, 'keyboard', '加入房间');
              await act(t, 'keyboard', '确认加入房间');
              expect(calls, [('a1', 'draft')]);
              expect(
                t.widget<TextField>(find.byType(TextField)).controller!.text,
                'draft',
              );
              await capture(t, boundary, '$name-keyboard-end');
            } finally {
              await t.pumpWidget(const SizedBox());
              await frames(t);
              enabled.dispose();
              debugDisableShadows = old;
            }
          },
        );
      }
    }
    testWidgets('$suite actual current room compact outlined toolbar review', (
      t,
    ) async {
      size(t, const Size(1000, 900));
      final port = HeldRoomPort(),
          views = <Map<String, Object?>>[],
          boundary = GlobalKey();
      final session = MenuRoomsSession(port, views.add)..show(true);
      try {
        await t.pump();
        await t.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: scopedApp(
              MenuRoomsPanel(
                view: MenuFeatureView.parse(views.last),
                onAction: session.act,
              ),
              suite,
            ),
          ),
        );
        await frames(t);
        expect(t.getSize(control('退出房间')).width, lessThan(200));
        await capture(t, boundary, '${suite.name}-room-toolbar');
        await act(t, 'pointer', '退出房间');
        await capture(t, boundary, '${suite.name}-room-leave-confirm');
        await act(t, 'pointer', '取消');
        expect(port.calls, isEmpty);
      } finally {
        await t.pumpWidget(const SizedBox());
        session.dispose();
        await t.pump(const Duration(seconds: 13));
      }
    });
  }
}
