import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/features/settings/application_support_check_action.dart';
import 'package:starbridge_flutter/features/settings/application_support_motion.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

Future<List<int>?> capture(
  WidgetTester t,
  GlobalKey key,
  String? name,
) => t.runAsync(() async {
  final image =
      await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
          .toImage();
  try {
    if (name != null) {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      final file = File('build/reviews/interaction-batch3df/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
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
          '$suite light=$light scale=$scale original icon-button geometry and wait pixels',
          (t) async {
            size(t, const Size(1000, 800));
            final controls = GlobalKey(), waiting = GlobalKey();
            final settings = ValueNotifier((false, true));
            var calls = 0;
            final prefix =
                '${suite.name}-${light ? 'light' : 'dark'}-${scale.toInt()}';
            try {
              await t.pumpWidget(
                ValueListenableBuilder<(bool, bool)>(
                  valueListenable: settings,
                  builder: (_, value, _) => scopedApp(
                    MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RepaintBoundary(
                            key: controls,
                            child: Material(
                              child: SizedBox(
                                width: 850,
                                height: 120,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    FilledButton.icon(
                                      key: const Key('native-check'),
                                      onPressed: value.$2 ? () {} : null,
                                      icon: const StarBridgeIcon(
                                        StarBridgeIconSemantic.refresh,
                                      ),
                                      label: const Text('重新检查'),
                                    ),
                                    ApplicationSupportCheckAction(
                                      controlKey: const Key('suite-check'),
                                      label: '重新检查',
                                      icon: StarBridgeIconSemantic.refresh,
                                      onActivate: value.$2
                                          ? (_) => calls++
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          RepaintBoundary(
                            key: waiting,
                            child: Material(
                              child: SizedBox(
                                width: 600,
                                child: const ApplicationSupportWaiting(
                                  source: InteractionSource.pointer,
                                  staticWait: false,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    suite,
                    light: light,
                    reduce: value.$1,
                  ),
                ),
              );
              await t.pump();
              await t.pump();
              await t.pump(const Duration(milliseconds: 16));
              expect(
                t.getSize(find.byKey(const Key('suite-check'))),
                t.getSize(find.byKey(const Key('native-check'))),
              );
              expect(
                t.getSize(find.byType(SuiteProgressBar)).width,
                greaterThan(100),
              );
              final before = await capture(t, controls, '$prefix-rest');
              final waitBefore = await capture(t, waiting, '$prefix-wait');
              final gesture = await t.startGesture(
                t.getCenter(find.byKey(const Key('suite-check'))),
              );
              await t.pump(const Duration(milliseconds: 120));
              await t.pump(const Duration(milliseconds: 80));
              expect(
                await capture(t, controls, '$prefix-press'),
                isNot(before),
              );
              expect(
                await capture(t, waiting, '$prefix-wait-moving'),
                isNot(waitBefore),
              );
              await gesture.cancel();
              await t.pump(const Duration(milliseconds: 600));
              expect(calls, 0);
              settings.value = (true, true);
              await t.pump();
              await t.pump();
              await t.pump(const Duration(milliseconds: 400));
              expect(find.byType(SuiteProgressBar), findsNothing);
              final reduced = await capture(t, waiting, '$prefix-reduce');
              await t.pump(const Duration(milliseconds: 200));
              expect(await capture(t, waiting, null), reduced);
              settings.value = (true, false);
              await t.pump();
              await t.pump();
              expect(
                t.getSize(find.byKey(const Key('suite-check'))),
                t.getSize(find.byKey(const Key('native-check'))),
              );
              await capture(t, controls, '$prefix-disabled');
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox());
              settings.dispose();
            }
          },
        );
      }
    }
  }
}
