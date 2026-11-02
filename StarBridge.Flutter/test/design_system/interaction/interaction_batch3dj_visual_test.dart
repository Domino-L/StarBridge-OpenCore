import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/settings/client_license.dart';
import 'package:starbridge_flutter/features/settings/client_license_dialog.dart';
import 'package:starbridge_flutter/features/settings/client_version_dialog.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3dj_test.dart' show activate, visibleFrames, remove;
import 'interaction_batch3dj_boundaries_test.dart' show mockCopy;

Future<void> capture(WidgetTester t, GlobalKey frame, String name) =>
    t.runAsync(() async {
      final image =
          await (frame.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      try {
        final file = File('build/reviews/interaction-batch3dj/$name.png');
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
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        final config =
            '${suite.name}-${light ? 'light' : 'dark'}-${scale.toInt()}';
        testWidgets(
          '$config narrow actual legal/version waiting and static reduce',
          (t) async {
            size(t, const Size(390, 800));
            t.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
            Completer<void>? copy;
            mockCopy(t, (call) async {
              if (call.method == 'Clipboard.setData') {
                await copy!.future;
              }
              return null;
            });
            for (final phase in ['license-read', 'version-read', 'copy']) {
              final license = phase == 'license-read';
              final licenseRead = Completer<ClientLicenseDocument>(),
                  versionRead = Completer<String?>();
              copy = Completer<void>();
              final frame = GlobalKey();
              Future<ClientLicenseDocument> readLicense() => licenseRead.future;
              Future<String?> readVersion() => phase == 'copy'
                  ? Future.value('1.2.3+build.123456789')
                  : versionRead.future;
              Widget host(bool reduce) => RepaintBoundary(
                key: frame,
                child: scopedApp(
                  license
                      ? ClientLicenseButton(
                          open: (context) => showClientLicenseDialog(
                            context,
                            read: readLicense,
                          ),
                        )
                      : ClientVersionButton(
                          open: (context) => showClientVersionDialog(
                            context,
                            read: readVersion,
                          ),
                        ),
                  suite,
                  light: light,
                  reduce: reduce,
                ),
              );
              await t.pumpWidget(host(false));
              await t.pumpAndSettle();
              await activate(
                t,
                license ? 'client-license-open' : 'client-version-open',
              );
              if (phase == 'copy') {
                await t.pumpAndSettle();
                await activate(t, 'client-version-copy');
              }
              await visibleFrames(t);
              expect(find.byType(HelpSupportWaiting), findsOneWidget);
              expect(find.byType(SuiteProgressBar), findsOneWidget);
              void bounds() {
                for (final key
                    in license
                        ? ['client-license-close', 'client-license-retry']
                        : [
                            'client-version-close',
                            'client-version-retry',
                            'client-version-copy',
                          ]) {
                  final rect = t.getRect(find.byKey(Key(key)));
                  expect(rect.left, greaterThanOrEqualTo(0));
                  expect(rect.right, lessThanOrEqualTo(390));
                  expect(rect.top, greaterThanOrEqualTo(0));
                  expect(rect.bottom, lessThanOrEqualTo(800));
                  expect(rect.height, lessThan(120));
                }
              }

              bounds();
              expect(t.takeException(), isNull);
              await capture(t, frame, '$config-$phase');
              await t.pumpWidget(host(true));
              await t.pump();
              await t.pump();
              expect(find.byType(SuiteProgressBar), findsNothing);
              expect(t.hasRunningAnimations, isFalse);
              bounds();
              await capture(t, frame, '$config-$phase-reduced');
              await remove(t);
              if (license) {
                licenseRead.complete(
                  const ClientLicenseDocument(ClientLicenseState.missing),
                );
              } else if (phase == 'version-read') {
                versionRead.complete(null);
              } else {
                copy.complete();
              }
              await t.pumpAndSettle();
              expect(t.takeException(), isNull);
            }
          },
        );
      }
    }
  }
}
