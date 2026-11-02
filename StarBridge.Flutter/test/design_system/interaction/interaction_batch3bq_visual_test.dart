import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/brand/scm_success_motion.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_page.dart';
import 'package:starbridge_flutter/features/account/account_port.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3bg_test.dart' show activate;
import 'interaction_batch3bq_test.dart' show LoginPort, clean;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  setUpAll(ScmSuccessMotion.verifyArtwork);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite signed-in narrow cache and logout proportions', (
      t,
    ) async {
      await loadFonts();
      t.view.physicalSize = const Size(430, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final p = LoginPort.signedIn(),
          module = createAccountModule(p),
          capture = GlobalKey();
      try {
        await module.initialize();
        await t.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: scopedApp(AccountPage(module: module), suite),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const Key('account-clear-cache')));
        for (final phase in ['session', 'cache-waiting']) {
          if (phase == 'cache-waiting') {
            p.heldType = ClearAccountProfileCache;
            p.held = Completer<AccountPortResult>();
            await activate(t, 'pointer', const Key('account-clear-cache'));
            await t.pump();
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
              'build/reviews/interaction-batch3bq/${suite.name}-430-$phase.png',
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
        p.held!.complete(AccountPortResult.completed(p.delegate.snapshot));
        p.held = null;
        await t.pumpAndSettle();
      } finally {
        await clean(t, module, p);
      }
    });
    for (final width in [430.0, 1100.0]) {
      testWidgets(
        '$suite width=$width account actions and loading modal review',
        (t) async {
          await loadFonts();
          t.view.physicalSize = Size(width, 900);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final p = LoginPort(),
              module = createAccountModule(p),
              capture = GlobalKey();
          try {
            await module.initialize();
            await t.pumpWidget(
              RepaintBoundary(
                key: capture,
                child: scopedApp(AccountPage(module: module), suite),
              ),
            );
            await t.pumpAndSettle();
            for (final phase in ['entry', 'waiting']) {
              if (phase == 'waiting') {
                await activate(t, 'pointer', const Key('account-login'));
                await t.runAsync(ScmSuccessMotion.verifyArtwork);
                await t.pump(const Duration(milliseconds: 350));
                await t.pump();
                expect(
                  find.byKey(const Key('account-login-dialog')),
                  findsOneWidget,
                );
                expect(
                  t
                      .widget<ScmSuccessMotion>(
                        find.byKey(const Key('account-login-motion')),
                      )
                      .loading,
                  isTrue,
                );
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
                  'build/reviews/interaction-batch3bq/${suite.name}-${width.toInt()}-$phase.png',
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
            await clean(t, module, p);
          }
        },
      );
    }
  }
}
