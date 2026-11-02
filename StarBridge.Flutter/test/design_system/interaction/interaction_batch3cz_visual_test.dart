import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/app/tray/tray_quick_panel.dart';
import 'package:starbridge_flutter/app/tray/tray_surface_app.dart';
import 'package:starbridge_flutter/app/tray/tray_surface_snapshot.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../../app/tray_surface_test.dart' show native;
import 'interaction_batch3ct_geometry_test.dart' show pixels;
import 'interaction_batch3cz_actions_test.dart' show fire;
import 'interaction_batch3cz_presence_test.dart' show menuSurface;

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/reviews/interaction-batch3cz');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$suite light=$light scale=$scale actual tray relay updates open popup and becomes static',
          (t) async {
            const channel = MethodChannel('starbridge/tray-surface');
            final calls = <MethodCall>[];
            final boundary = GlobalKey();
            t.view.devicePixelRatio = 1;
            t.view.physicalSize = const Size(360, 1000);
            t.platformDispatcher.textScaleFactorTestValue = scale;
            final initial = {
              ...TraySurfaceSnapshot(
                scope: 4,
                state: const TrayQuickPanelState(
                  runtime: TrayRuntimeState.running,
                  overlay: TrayOverlayState.enabled,
                  version: '1.0 test',
                  scene: '本地验证场景',
                ),
                presence: PresenceVisibility.online,
                canChangePresence: true,
                canToggleOverlay: true,
                interactionStyle: suite.name,
                dark: !light,
              ).toMap(),
              'opening': 1,
            };
            t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
              call,
            ) async {
              calls.add(call);
              return call.method == 'ready' ? initial : null;
            });
            try {
              await t.pumpWidget(
                RepaintBoundary(key: boundary, child: const TraySurfaceApp()),
              );
              await t.pumpAndSettle();
              expect(find.byType(TrayQuickPanel), findsOneWidget);
              await t.runAsync(() async {
                final context = t.element(find.byType(TrayQuickPanel));
                await Future.wait([
                  for (final brightness in ['dark', 'light'])
                    precacheImage(
                      AssetImage(
                        'assets/brand/small_icons/${brightness}_surface/36.png',
                      ),
                      context,
                    ),
                ]);
              });
              await t.pumpAndSettle();
              final name = '${suite.name}-${light ? 'light' : 'dark'}-$scale';
              await capture(t, boundary, '$name-initial');
              final idle = await pixels(t, boundary);
              final press = await t.startGesture(
                t.getCenter(find.byKey(const Key('tray-open'))),
              );
              await t.pump();
              await t.pump(const Duration(milliseconds: 30));
              expect(await pixels(t, boundary), isNot(orderedEquals(idle)));
              await capture(t, boundary, '$name-pressed');
              await press.cancel();
              await t.pumpAndSettle();
              expect(calls.where((c) => c.method == 'action'), isEmpty);
              await fire(t, 'pointer', 'tray-presence-menu');
              await t.pump();
              await t.pump();
              expect(menuSurface(), findsOneWidget);
              expect(
                t.widget<SuiteSurfaceTransition>(menuSurface()).animation.value,
                lessThan(1),
              );
              await t.pump(const Duration(milliseconds: 50));
              final next = InteractionSuite.values[(suite.index + 1) % 4];
              await native(t.binding, channel.name, 'snapshot', {
                ...initial,
                'revision': 1,
                'interactionStyle': next.name,
                'dark': light,
                'reduceMotion': true,
              });
              await t.pump();
              await t.pump();
              expect(menuSurface(), findsOneWidget);
              expect(
                t.widget<SuiteSurfaceTransition>(menuSurface()).animation.value,
                1,
              );
              final effective = InteractionScope.of(t.element(menuSurface()));
              expect(effective.suite, next);
              expect(effective.reduceMotion, isTrue);
              expect(calls.where((c) => c.method == 'action'), isEmpty);
              expect(calls.where((c) => c.method == 'painted'), hasLength(1));
              await capture(t, boundary, '$name-reduced');
              final still = await pixels(t, boundary);
              await t.pump(const Duration(milliseconds: 80));
              expect(await pixels(t, boundary), orderedEquals(still));
              final rect = t.getRect(menuSurface());
              expect(rect.left, greaterThanOrEqualTo(8));
              expect(rect.right, lessThanOrEqualTo(352));
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
              await t.pump();
              await t.pump();
              expect(menuSurface(), findsNothing);
              expect(calls.where((c) => c.method == 'dismiss'), isEmpty);
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
              await t.pump();
              expect(calls.where((c) => c.method == 'dismiss'), hasLength(1));
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox());
              await t.pump();
              t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                channel,
                null,
              );
              t.view.reset();
              t.platformDispatcher.clearTextScaleFactorTestValue();
            }
          },
        );
      }
    }
  }
}
