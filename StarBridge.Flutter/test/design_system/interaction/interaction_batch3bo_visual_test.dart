import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/settings/event_scope_editor.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';

import '../../features/settings/community_sharing_test.dart'
    show SharingFixture, target;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bo_test.dart' show scopeApp, clean;

void main() {
  for (final suite in InteractionSuite.values) {
    for (final width in [430.0, 1100.0]) {
      testWidgets(
        '$suite width=$width room organization and event controls review',
        (t) async {
          await loadFonts();
          t.view.physicalSize = Size(width, 1000);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final p = SharingFixture(),
              c = LocalPrivacyController(p),
              capture = GlobalKey();
          try {
            await c.refresh();
            c.enableCommunityChoices();
            c.editCommunity(
              target('A')
                  .choice(fields: 3)
                  .copyWith(
                    allMembersCanView: false,
                    administratorsCanView: true,
                  ),
            );
            for (final kind in ['room', 'organization', 'event']) {
              final child = kind == 'event'
                  ? scopedApp(
                      const SingleChildScrollView(
                        child: EventScopeEditor(
                          scopeKey: 'review-event',
                          title: '事件共享',
                          description: '独立事件范围',
                          choice: EventSharingChoice(
                            enabled: true,
                            selectedTypes: 47,
                          ),
                          canEdit: true,
                          onChanged: ignore,
                        ),
                      ),
                      suite,
                    )
                  : scopeApp(c, suite, kind);
              await t.pumpWidget(RepaintBoundary(key: capture, child: child));
              await t.pumpAndSettle();
              t.binding.scheduleFrame();
              await t.pump(const Duration(milliseconds: 16));
              expect(t.takeException(), isNull);
              final image = (await t.runAsync(
                () =>
                    (capture.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage(),
              ))!;
              try {
                final bytes = (await t.runAsync(
                  () => image.toByteData(format: ui.ImageByteFormat.png),
                ))!;
                final file = File(
                  'build/reviews/interaction-batch3bo/${suite.name}-${width.toInt()}-$kind.png',
                );
                file.parent.createSync(recursive: true);
                file.writeAsBytesSync(
                  bytes.buffer.asUint8List(
                    bytes.offsetInBytes,
                    bytes.lengthInBytes,
                  ),
                );
              } finally {
                image.dispose();
              }
            }
          } finally {
            await clean(t, c, p);
          }
        },
      );
    }
  }
}

void ignore(EventSharingChoice _) {}
