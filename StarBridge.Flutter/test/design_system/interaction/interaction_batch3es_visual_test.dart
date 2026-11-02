import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/entitlement_redemption_dialog.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3eo_test.dart' show activate, key;
import 'interaction_batch3eq_test.dart' show validationApp;

void main() {
  testWidgets(
    'redemption waiting and unconfirmed result fit narrow scaled dialog',
    (t) async {
      const output = String.fromEnvironment('INTERACTION_CAPTURE_DIR');
      await loadFonts();
      for (final suite in [
        InteractionSuite.rail,
        InteractionSuite.scan,
        InteractionSuite.glow,
      ]) {
        for (final light in [false, true]) {
          for (final locale in [
            const Locale('zh', 'CN'),
            const Locale('zh', 'TW'),
            const Locale('en'),
          ]) {
            size(t, const Size(500, 900));
            final frame = GlobalKey();
            final pending = Completer<String>();
            await t.pumpWidget(
              RepaintBoundary(
                key: frame,
                child: validationApp(
                  EntitlementRedemptionDialog(
                    supported: true,
                    redeem: (_) => pending.future,
                  ),
                  suite,
                  light: light,
                  locale: locale,
                  scale: 1.5,
                ),
              ),
            );
            await t.pumpAndSettle();
            await t.enterText(find.byType(TextField), 'synthetic-code');
            await t.pumpAndSettle();
            await activate(t, key('redemption-submit'), 'pointer');
            await t.pump(const Duration(milliseconds: 260));
            expect(t.takeException(), isNull);
            if (output.isNotEmpty && locale.countryCode == 'CN') {
              await t.runAsync(() async {
                final image =
                    await (frame.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary)
                        .toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await Directory(output).create(recursive: true);
                await File(
                  '$output/${suite.name}-${light ? 'light' : 'dark'}-waiting.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            pending.complete('uncertain');
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            // The original result remains readable and the original close action
            // remains inside the viewport at larger text sizes.
            final close = t.getRect(key('redemption-close'));
            expect(close.left, greaterThanOrEqualTo(0));
            expect(close.right, lessThanOrEqualTo(500));
            expect(close.bottom, lessThanOrEqualTo(900));
            await t.pumpWidget(const SizedBox());
          }
        }
      }
    },
  );
}
