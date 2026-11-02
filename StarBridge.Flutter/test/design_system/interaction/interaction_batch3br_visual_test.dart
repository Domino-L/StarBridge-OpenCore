import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/brand/scm_success_motion.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_page.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3bg_test.dart' show activate;
import 'interaction_batch3bq_test.dart' show clean;
import 'interaction_batch3br_test.dart' show PreferencesPort;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  setUpAll(ScmSuccessMotion.verifyArtwork);
  for (final suite in InteractionSuite.values) {
    for (final width in [430.0, 1100.0]) {
      testWidgets(
        '$suite width=$width preferences draft waiting refusal review',
        (t) async {
          await loadFonts();
          t.view.physicalSize = Size(width, 900);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final p = PreferencesPort(),
              m = createAccountModule(p),
              capture = GlobalKey();
          try {
            await m.initialize();
            await t.pumpWidget(
              RepaintBoundary(
                key: capture,
                child: scopedApp(
                  AccountPage(module: m),
                  suite,
                  light: width > 1000,
                ),
              ),
            );
            await t.runAsync(ScmSuccessMotion.verifyArtwork);
            await t.pumpAndSettle();
            m.preferencesDraft.setLocale('en-US');
            await t.pumpAndSettle();
            await t.ensureVisible(
              find.byKey(const Key('account-save-preferences')),
            );
            for (final phase in ['draft', 'waiting', 'refused']) {
              if (phase == 'waiting') {
                p.heldType = SaveAccountPreferences;
                p.held = Completer<AccountPortResult>();
                await activate(
                  t,
                  'pointer',
                  const Key('account-save-preferences'),
                );
              } else if (phase == 'refused') {
                p.held!.complete(
                  const AccountPortResult.failed(
                    AccountFailure(
                      code: 'refused',
                      messageKey: 'account.preferences.readOnly',
                      retryable: true,
                    ),
                  ),
                );
                p.held = null;
                await t.pumpAndSettle();
                expect(m.preferencesDraft.hasChanges, isTrue);
              }
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
                  'build/reviews/interaction-batch3br/${suite.name}-${width.toInt()}-$phase.png',
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
            await clean(t, m, p);
          }
        },
      );
    }
  }
}
