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
import 'package:starbridge_flutter/features/account/legacy_password_login.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3bt_test.dart' show hit;
import 'interaction_batch3bu_test.dart' show LoginPort, cleanup;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  setUpAll(ScmSuccessMotion.verifyArtwork);
  for (final suite in InteractionSuite.values) {
    for (final config in [(430.0, 1.0), (1100.0, 1.0), (430.0, 2.0)]) {
      testWidgets(
        '$suite width=${config.$1} text=${config.$2} legacy login review',
        (t) async {
          await loadFonts();
          t.view.physicalSize = Size(config.$1, 900);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final p = LoginPort(),
              m = createAccountModule(p),
              capture = GlobalKey();
          try {
            await m.initialize();
            final base = scopedApp(
              AccountPage(module: m),
              suite,
              light: config.$1 > 1000,
            ) as MaterialApp;
            await t.pumpWidget(
              RepaintBoundary(
                key: capture,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: base.theme,
                  locale: base.locale,
                  supportedLocales: base.supportedLocales,
                  localizationsDelegates: base.localizationsDelegates,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(config.$2)),
                    child: base.builder!(context, child),
                  ),
                  home: base.home,
                ),
              ),
            );
            await t.pumpAndSettle();
            await hit(t, 'pointer', 'account-legacy-login');
            await t.pumpAndSettle();
            for (final phase in ['form', 'invalid', 'waiting']) {
              if (phase == 'invalid') {
                await hit(t, 'pointer', 'legacy-login-submit');
                await t.pumpAndSettle();
              } else if (phase == 'waiting') {
                await t.enterText(
                  find.byKey(const Key('legacy-login-email')),
                  'old@example.invalid',
                );
                await t.enterText(
                  find.byKey(const Key('legacy-login-password')),
                  'unit-test-only',
                );
                await t.pump();
                await t.pump(const Duration(milliseconds: 220));
                p.pendingLogin = Completer<LegacyPasswordLoginResult>();
                await hit(t, 'pointer', 'legacy-login-submit');
                expect(find.byType(SuiteProgressBar), findsOneWidget);
              }
              await t.ensureVisible(
                find.byKey(const Key('legacy-login-close')),
              );
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
                  'build/reviews/interaction-batch3bu/${suite.name}-${config.$1.toInt()}-${config.$2}-$phase.png',
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
            await cleanup(t, m, p);
          }
        },
      );
    }
  }
}
