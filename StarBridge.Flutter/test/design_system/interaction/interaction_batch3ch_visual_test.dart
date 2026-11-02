import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/communities/community_announcement_details.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../../app/menu_overlay/menu_announcement_details_control_test.dart'
    show fixture;
import 'interaction_batch3ca_visual_test.dart' show viewport;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3ch_test.dart'
    show Harness, HarnessState, PanelFixture, activate, route;

Future<void> capture(WidgetTester t, GlobalKey boundary, String name) async {
  expect(t.takeException(), isNull);
  final image = (await t.runAsync(
    () =>
        (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(),
  ))!;
  try {
    final data = (await t.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    final file = File('build/reviews/interaction-batch3ch/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image.dispose();
  }
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final config in [(430.0, 1.0), (1100.0, 1.0), (430.0, 2.0)]) {
      testWidgets(
        '$suite $config details entrance/wait/failure/retained exit',
        (t) async {
          await loadFonts();
          viewport(t, config);
          final old = debugDisableShadows;
          debugDisableShadows = false;
          final boundary = GlobalKey();
          final name = '${suite.name}-${config.$1.toInt()}-${config.$2}';
          try {
            await t.pumpWidget(
              RepaintBoundary(key: boundary, child: Harness(suite)),
            );
            final h = t.state<HarnessState>(find.byType(Harness));
            h.change(() {
              h.light = config.$1 > 1000;
              h.raw = fixture(loading: true, long: true);
            });
            await frames(t);
            await capture(t, boundary, '$name-entry');
            await activate(t, 'pointer', 'menu-announcement-details-open');
            await t.pump();
            await t.pump(const Duration(milliseconds: 80));
            await capture(t, boundary, '$name-enter');
            await frames(t);
            await Scrollable.ensureVisible(
              t.element(find.byType(SuiteProgressBar)),
              alignment: .45,
            );
            await frames(t);
            await capture(t, boundary, '$name-wait');
            h.change(() => h.reduce = true);
            await t.pump();
            await t.pump();
            await capture(t, boundary, '$name-static-wait');
            h.change(() => h.raw = fixture(failed: true));
            await frames(t);
            await t.ensureVisible(
              find.byKey(const Key('announcement-detail-retry')),
            );
            await capture(t, boundary, '$name-failed');
            h.change(() => h.reduce = false);
            await frames(t);
            final r = route(t);
            await activate(t, 'pointer', 'menu-announcement-details-close');
            await t.pump();
            await t.pump(const Duration(milliseconds: 40));
            if (suite != InteractionSuite.standard) {
              expect(r.animation!.value, greaterThan(0));
              expect(
                find.byType(CommunityAnnouncementDetailsBody),
                findsOneWidget,
              );
            }
            await capture(t, boundary, '$name-exit');
            await frames(t);
            expect(find.byType(AlertDialog), findsNothing);
            await capture(t, boundary, '$name-closed');
          } finally {
            debugDisableShadows = old;
            await t.pumpWidget(const SizedBox());
            await frames(t);
          }
        },
      );
      testWidgets('$suite $config actual organization panel/session review', (
        t,
      ) async {
        await loadFonts();
        viewport(t, config);
        final old = debugDisableShadows;
        debugDisableShadows = false;
        final f = PanelFixture(), boundary = GlobalKey();
        final name = '${suite.name}-${config.$1.toInt()}-${config.$2}';
        try {
          await f.ready(t);
          f.port.gate = Completer<Map<String, Object?>>();
          await t.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: f.page(suite, light: config.$1 > 1000),
            ),
          );
          await frames(t);
          await t.ensureVisible(
            find.byKey(const Key('menu-announcement-details-open')),
          );
          await capture(t, boundary, '$name-panel');
          await activate(t, 'pointer', 'menu-announcement-details-open');
          await t.pump();
          await t.pump();
          await frames(t);
          await capture(t, boundary, '$name-panel-wait');
          final producer = f.port.gate;
          // Finish using the same existing fake port's valid detail serializer.
          f.port.gate = null;
          final body = await f.port.readAnnouncementDetail(
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            0,
            null,
          );
          producer!.complete(body);
          await frames(t);
          expect(find.byType(SuiteProgressBar), findsNothing);
          await capture(t, boundary, '$name-panel-ready');
        } finally {
          debugDisableShadows = old;
          await f.close(t);
        }
      });
    }
  }
}
