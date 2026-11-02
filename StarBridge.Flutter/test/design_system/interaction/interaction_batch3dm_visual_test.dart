import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_motion_controls.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;

Future<void> capture(WidgetTester t, GlobalKey key, String name) => t.runAsync(
  () async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/reviews/interaction-batch3dm/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  },
);

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        final config =
            '${suite.name}-${light ? 'light' : 'dark'}-${scale.toInt()}';
        testWidgets('$config executive controls preserve native geometry', (
          t,
        ) async {
          size(t, const Size(840, 1100));
          t.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          final frame = GlobalKey();
          Widget button(String id, int kind) => switch (kind) {
            0 => TextButton.icon(
              key: Key(id),
              onPressed: () {},
              icon: const StandardIcon(
                StandardIconSemantic.expandMore,
                size: 18,
              ),
              label: const Text('调整监测'),
            ),
            1 => FilledButton.tonal(
              key: Key(id),
              onPressed: () {},
              child: const Text('保存提醒设置'),
            ),
            _ => OutlinedButton.icon(
              key: Key(id),
              onPressed: () {},
              icon: const StandardIcon(
                StandardIconSemantic.dashboard,
                size: 18,
              ),
              label: const Text('添加到菜单'),
            ),
          };
          Widget checkbox(String id) => CheckboxListTile(
            key: Key(id),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('开启时提醒', key: Key('$id-title')),
            value: true,
            onChanged: (_) {},
          );
          Widget toggle(String id) => SwitchListTile(
            key: Key(id),
            contentPadding: EdgeInsets.zero,
            title: Text('随游戏自动监测', key: Key('$id-title')),
            subtitle: const Text('保存后才会应用'),
            value: true,
            onChanged: (_) {},
          );
          await t.pumpWidget(
            RepaintBoundary(
              key: frame,
              child: scopedApp(
                Center(
                  child: SizedBox(
                    width: 390,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ExecHangarMotionButton(
                              button('adapted-$i', i) as ButtonStyleButton,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: button('native-$i', i),
                          ),
                        ],
                        KeyedSubtree(
                          key: const Key('adapted-check-row'),
                          child: execHangarCheckbox(
                            checkbox('adapted-check') as CheckboxListTile,
                          ),
                        ),
                        KeyedSubtree(
                          key: const Key('native-check-row'),
                          child: checkbox('native-check'),
                        ),
                        KeyedSubtree(
                          key: const Key('adapted-switch-row'),
                          child: execHangarSwitch(
                            toggle('adapted-switch') as SwitchListTile,
                          ),
                        ),
                        KeyedSubtree(
                          key: const Key('native-switch-row'),
                          child: toggle('native-switch'),
                        ),
                      ],
                    ),
                  ),
                ),
                suite,
                light: light,
              ),
            ),
          );
          await t.pumpAndSettle();
          for (var i = 0; i < 3; i++) {
            expect(
              t.getSize(find.byKey(Key('adapted-$i'))),
              t.getSize(find.byKey(Key('native-$i'))),
              reason: '$config native button $i',
            );
          }
          for (final kind in ['check', 'switch']) {
            final a = find.byKey(Key('adapted-$kind-row')),
                b = find.byKey(Key('native-$kind-row'));
            expect(
              t.getSize(a),
              t.getSize(b),
              reason: '$config native $kind row',
            );
            final aLabel =
                t.getTopLeft(find.byKey(Key('adapted-$kind-title'))) -
                t.getTopLeft(a);
            final bLabel =
                t.getTopLeft(find.byKey(Key('native-$kind-title'))) -
                t.getTopLeft(b);
            expect(aLabel, bLabel, reason: '$config native $kind title origin');
          }
          await capture(t, frame, '$config-native-controls');
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
