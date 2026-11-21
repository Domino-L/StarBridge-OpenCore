import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profile_view.dart';
import 'package:starbridge_flutter/features/gameplay_time/gameplay_time_controller.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_summary.dart';

import '../features/gameplay_time/gameplay_time_test.dart' as support;
import '../features/friends/social_layout_test.dart' show loadFonts;
import '../app/menu_overlay/menu_profiles_session_test.dart'
    show fixtureProfile;

void main() {
  setUpAll(loadFonts);
  for (final width in [360.0, 1100.0]) {
    for (final state in ['available', 'empty', 'unavailable']) {
      testWidgets('owner playtime summary review at $width: $state', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 640);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final h = support.Harness();
        await tester.pump();
        h.controller.value = GameplayTimeView(
          seconds: 614 * 3600,
          historicalSeconds: 604 * 3600 + 34 * 60,
          accountTotalState: state,
          accountTotalSeconds: state == 'available' ? 7200 : null,
        );
        final profile = MenuProfileView.parse({
          ...MenuProfileView.encode(fixtureProfile),
          'minutes': null,
        }).snapshot!;
        final key = GlobalKey();
        await tester.pumpWidget(
          support.app(
            Padding(
              padding: const EdgeInsets.all(12),
              child: RepaintBoundary(
                key: key,
                child: PersonalProfileSummaryStrip(
                  projection: PersonalProfileProjection.fromSnapshot(profile),
                  gameplayTime: h.controller,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('614小时 0分钟'), findsOneWidget);
        expect(
          find.textContaining(switch (state) {
            'available' => '账号累计 2 小时',
            'empty' => '账号还没有云端累计',
            _ => '账号累计暂时读不到',
          }),
          findsOneWidget,
        );
        expect(find.textContaining('账号累计 0 小时'), findsNothing);
        expect(tester.takeException(), isNull);
        const output = String.fromEnvironment('PROFILE_PLAYTIME_REVIEW_OUTPUT');
        if (output.isNotEmpty) {
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(output).create(recursive: true);
              final suffix = state == 'unavailable' ? '' : '-$state';
              await File('$output/owner-${width.toInt()}$suffix.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
        }
        await tester.pumpWidget(const SizedBox());
        await h.close(tester);
      });
    }
  }
}
