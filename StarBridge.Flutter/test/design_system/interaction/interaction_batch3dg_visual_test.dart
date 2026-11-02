import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/settings/help_support_action.dart';
import 'package:starbridge_flutter/features/settings/help_support_settings_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

Future<List<int>?> capture(WidgetTester t, GlobalKey key, String? name) =>
    t.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      try {
        if (name != null) {
          final file = File('build/reviews/interaction-batch3dg/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(
            (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
                .asUint8List(),
          );
        }
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List()
            .toList();
      } finally {
        image.dispose();
      }
    });

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$suite light=$light textScale=$scale native geometry and active feedback',
          (t) async {
            size(t, const Size(1200, 800));
            final key = GlobalKey();
            final enabled = ValueNotifier(true);
            var calls = 0;
            final name =
                '${suite.name}-${light ? 'light' : 'dark'}-${scale.toInt()}';
            try {
              await t.pumpWidget(
                ValueListenableBuilder<bool>(
                  valueListenable: enabled,
                  builder: (_, value, _) => scopedApp(
                    MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: Center(
                        child: RepaintBoundary(
                          key: key,
                          child: Material(
                            child: SizedBox(
                              width: 1000,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final mode in [
                                    'text',
                                    'outlined',
                                    'icon',
                                  ])
                                    SizedBox(
                                      height: 96,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceEvenly,
                                        children: [
                                          switch (mode) {
                                            'text' => TextButton(
                                              key: Key('native-$mode'),
                                              onPressed: value ? () {} : null,
                                              child: const Text('关闭'),
                                            ),
                                            'outlined' => OutlinedButton(
                                              key: Key('native-$mode'),
                                              onPressed: value ? () {} : null,
                                              child: const Text('赞助'),
                                            ),
                                            _ => OutlinedButton.icon(
                                              key: Key('native-$mode'),
                                              onPressed: value ? () {} : null,
                                              icon: const StarBridgeIcon(
                                                StarBridgeIconSemantic.refresh,
                                              ),
                                              label: const Text('检查更新'),
                                            ),
                                          },
                                          HelpSupportAction(
                                            controlKey: Key('suite-$mode'),
                                            kind: mode == 'text'
                                                ? StarBridgeActionKind.quiet
                                                : StarBridgeActionKind
                                                      .secondary,
                                            icon: mode == 'icon'
                                                ? StarBridgeIconSemantic.refresh
                                                : null,
                                            onActivate: value
                                                ? (_) => calls++
                                                : null,
                                            child: Text(
                                              mode == 'text'
                                                  ? '关闭'
                                                  : mode == 'outlined'
                                                  ? '赞助'
                                                  : '检查更新',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    suite,
                    light: light,
                  ),
                ),
              );
              await t.pumpAndSettle();
              void geometry() {
                for (final mode in ['text', 'outlined', 'icon']) {
                  expect(
                    t.getSize(find.byKey(Key('suite-$mode'))),
                    t.getSize(find.byKey(Key('native-$mode'))),
                    reason: '$mode original public button geometry',
                  );
                }
              }

              geometry();
              final rest = await capture(t, key, '$name-rest');
              final gesture = await t.startGesture(
                t.getCenter(find.byKey(const Key('suite-outlined'))),
              );
              await t.pump();
              await t.pump(const Duration(milliseconds: 100));
              expect(await capture(t, key, '$name-press'), isNot(rest));
              await gesture.cancel();
              await t.pumpAndSettle();
              expect(calls, 0);
              enabled.value = false;
              await t.pumpAndSettle();
              geometry();
              await capture(t, key, '$name-disabled');
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox());
              enabled.dispose();
            }
          },
        );
      }
      for (final width in [390.0, 1400.0]) {
        testWidgets(
          '$suite light=$light help page width=$width offline frames',
          (t) async {
            size(t, Size(width, 1000));
            final key = GlobalKey();
            await t.pumpWidget(
              scopedApp(
                Builder(
                  builder: (context) => RepaintBoundary(
                    key: key,
                    child: ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: const HelpSupportSettingsPage(),
                    ),
                  ),
                ),
                suite,
                light: light,
              ),
            );
            await t.pumpAndSettle();
            await capture(
              t,
              key,
              '${suite.name}-${light ? 'light' : 'dark'}-${width.toInt()}-page',
            );
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
