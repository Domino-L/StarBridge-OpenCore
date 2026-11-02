import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/legal/third_party_license_browser.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3dk_test.dart';
import 'interaction_batch3dj_test.dart' show visibleFrames, remove;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;

Future<void> capture(WidgetTester t, GlobalKey frame, String name) =>
    t.runAsync(() async {
      final image =
          await (frame.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      try {
        final file = File('build/reviews/interaction-batch3dk/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(
          (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
              .asUint8List(),
        );
      } finally {
        image.dispose();
      }
    });

void main() {
  setUpAll(loadFonts);
  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        final config =
            '${suite.name}-${light ? 'light' : 'dark'}-${scale.toInt()}';
        testWidgets('$config narrow and wide actual directory/details', (
          t,
        ) async {
          size(t, const Size(390, 800));
          t.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          LicenseRegistry.addLicense(() async* {
            yield Entry(['StarBridge'], 'LICENSE');
            yield Entry(['Source Sans 3'], 'Font license');
            yield Entry([
              'Very long library package name for overflow coverage',
            ], 'Long library license');
          });
          final host = GlobalKey<HostState>(), frame = GlobalKey();
          await t.pumpWidget(
            RepaintBoundary(
              key: frame,
              child: Host(suite, key: host),
            ),
          );
          host.currentState!.change(() => host.currentState!.light = light);
          await t.pumpAndSettle();
          await activate(t, 'open');
          await settleRead(t);
          expect(find.byType(ThirdPartyLicenseBrowser), findsOneWidget);
          void backBounds(double width) {
            final rect = t.getRect(find.byKey(const Key('license-back')));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
            expect(rect.height, lessThanOrEqualTo(56));
          }

          backBounds(390);
          expect(t.takeException(), isNull);
          await capture(t, frame, '$config-narrow-directory');
          await activate(t, 'license-package-StarBridge');
          await t.pump();
          await t.pump(const Duration(milliseconds: 80));
          await capture(t, frame, '$config-narrow-enter');
          await settleRead(t);
          backBounds(390);
          expect(t.takeException(), isNull);
          await capture(t, frame, '$config-narrow-detail');
          t.view.physicalSize = const Size(1280, 900);
          await settleRead(t);
          backBounds(1280);
          expect(t.takeException(), isNull);
          await capture(t, frame, '$config-wide-detail');
          host.currentState!.change(() => host.currentState!.reduce = true);
          await visibleFrames(t);
          await capture(t, frame, '$config-wide-reduced');
          expect(t.takeException(), isNull);
          await remove(t);
        });
      }
    }
  }
}
