import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_page.dart';
import 'package:starbridge_flutter/features/settings/help_support_action.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/platform/window/native_viewport_visibility.dart';

import 'interaction_batch3dl_test.dart';
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3dk_test.dart' show activate;
import 'interaction_batch3dj_test.dart' show visibleFrames, remove;
import 'interaction_batch3cn_visual_test.dart' show pixels;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;

Future<void> capture(WidgetTester t, GlobalKey frame, String name) =>
    t.runAsync(() async {
      final image =
          await (frame.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      try {
        final path = File('build/reviews/interaction-batch3dl/$name.png');
        await path.parent.create(recursive: true);
        await path.writeAsBytes(
          (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
              .asUint8List(),
        );
      } finally {
        image.dispose();
      }
    });

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        final config =
            '${suite.name}-${light ? 'light' : 'dark'}-${scale.toInt()}';
        testWidgets(
          '$config notification actions keep native geometry, pending marker moves then becomes static',
          (t) async {
            size(t, const Size(390, 850));
            t.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
            final frame = GlobalKey();
            await t.pumpWidget(
              RepaintBoundary(
                key: frame,
                child: scopedApp(
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final outlined in [false, true]) ...[
                          HelpSupportAction(
                            controlKey: Key('adapted-$outlined'),
                            kind: outlined
                                ? StarBridgeActionKind.secondary
                                : StarBridgeActionKind.quiet,
                            onActivate: (_) {},
                            child: Text(outlined ? '前往相关页面' : '刷新'),
                          ),
                          if (outlined)
                            OutlinedButton(
                              key: const Key('native-true'),
                              onPressed: () {},
                              child: const Text('前往相关页面'),
                            )
                          else
                            TextButton(
                              key: const Key('native-false'),
                              onPressed: () {},
                              child: const Text('刷新'),
                            ),
                        ],
                      ],
                    ),
                  ),
                  suite,
                  light: light,
                ),
              ),
            );
            await t.pumpAndSettle();
            for (final outlined in [false, true]) {
              expect(
                t.getSize(find.byKey(Key('adapted-$outlined'))),
                t.getSize(find.byKey(Key('native-$outlined'))),
              );
            }
            await capture(t, frame, '$config-native-geometry');
            final inbox = Inbox();
            Widget host(bool reduce) => RepaintBoundary(
              key: frame,
              child: scopedApp(
                NativeViewportScope(
                  active: false,
                  child: NotificationInboxPage(
                    controller: inbox,
                    openSafety: () {},
                  ),
                ),
                suite,
                reduce: reduce,
                light: light,
              ),
            );
            await t.pumpWidget(host(false));
            await t.pumpAndSettle();
            inbox.next = Completer<bool>();
            await activate(t, 'notification-refresh');
            await t.pump();
            await t.pump(const Duration(milliseconds: 60));
            final wait = find
                .descendant(
                  of: find.byType(SocialReadActivity),
                  matching: find.byType(RepaintBoundary),
                )
                .first;
            final before = await pixels(t, wait);
            await t.pump(const Duration(milliseconds: 350));
            expect(await pixels(t, wait), isNot(orderedEquals(before)));
            final markerRect = t.getRect(find.byType(SocialReadActivity));
            expect(markerRect.height, 4);
            expect(markerRect.left, greaterThanOrEqualTo(0));
            expect(markerRect.right, lessThanOrEqualTo(390));
            expect(t.takeException(), isNull);
            await capture(t, frame, '$config-notification-pending');
            await t.pumpWidget(host(true));
            await visibleFrames(t);
            expect(waitData(t).reduceMotion, isTrue);
            final frozen = await pixels(t, wait);
            await t.pump(const Duration(milliseconds: 250));
            expect(await pixels(t, wait), orderedEquals(frozen));
            expect(t.takeException(), isNull);
            await capture(t, frame, '$config-notification-reduced');
            await remove(t);
            inbox.next!.complete(true);
            await t.pump();
            inbox.dispose();
          },
        );
      }
    }
  }
}
