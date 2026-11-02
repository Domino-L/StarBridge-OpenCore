import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/app/tray/tray_quick_panel.dart';
import 'package:starbridge_flutter/app/tray/tray_surface_app.dart';
import 'package:starbridge_flutter/app/tray/tray_surface_snapshot.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/tray_surface_test.dart' show native;
import '../../features/friends/social_layout_test.dart' show loadFonts;
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
      final dir = Directory('build/reviews/interaction-batch3da');
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
      for (final mode in ['initial-reduce', 'live-reduce', 'keyboard']) {
        for (final input in ['keyboard', 'hover']) {
          if (mode == 'keyboard' && input == 'hover') continue;
          testWidgets(
            '$suite light=$light mode=$mode $input actual tray menu static feedback',
            (t) async {
              const channel = MethodChannel('starbridge/tray-surface');
              final calls = <MethodCall>[];
              final boundary = GlobalKey();
              t.view.devicePixelRatio = 1;
              t.view.physicalSize = const Size(360, 1000);
              final initial = {
                ...TraySurfaceSnapshot(
                  scope: 4,
                  state: const TrayQuickPanelState(
                    runtime: TrayRuntimeState.running,
                    overlay: TrayOverlayState.enabled,
                  ),
                  presence: PresenceVisibility.online,
                  canChangePresence: true,
                  interactionStyle: suite.name,
                  dark: !light,
                  reduceMotion: mode == 'initial-reduce',
                ).toMap(),
                'opening': 1,
              };
              t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                channel,
                (call) async {
                  calls.add(call);
                  return call.method == 'ready' ? initial : null;
                },
              );
              TestGesture? mouse;
              try {
                await t.pumpWidget(
                  RepaintBoundary(key: boundary, child: const TraySurfaceApp()),
                );
                await t.pumpAndSettle();
                await t.runAsync(() async {
                  await precacheImage(
                    AssetImage(
                      'assets/brand/small_icons/${light ? 'light' : 'dark'}_surface/36.png',
                    ),
                    t.element(find.byType(TrayQuickPanel)),
                  );
                });
                await t.pumpAndSettle();
                await fire(t, 'keyboard', 'tray-presence-menu');
                await t.pump();
                await t.pump();
                expect(menuSurface(), findsOneWidget);
                if (mode == 'live-reduce') {
                  await native(t.binding, channel.name, 'snapshot', {
                    ...initial,
                    'revision': 1,
                    'reduceMotion': true,
                  });
                  await t.pump();
                  await t.pump();
                }
                expect(
                  InteractionScope.of(t.element(menuSurface())).reduceMotion,
                  mode != 'keyboard',
                );
                if (input == 'hover') {
                  mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
                  await mouse.addPointer(location: const Offset(355, 990));
                  await t.pumpAndSettle();
                }
                final before = await pixels(t, boundary);
                if (input == 'keyboard') {
                  await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
                } else {
                  final row = find.byKey(
                    const Key('manual-presence-invisible'),
                  );
                  expect(row, findsOneWidget);
                  await mouse!.moveTo(t.getCenter(row));
                }
                await t.pump();
                await t.pump();
                final changed = await pixels(t, boundary);
                expect(
                  changed,
                  isNot(orderedEquals(before)),
                  reason: 'Feedback must be visible, not removed',
                );
                await capture(t, boundary, '${suite.name}-$light-$mode-$input');
                await t.pump(const Duration(milliseconds: 80));
                expect(
                  await pixels(t, boundary),
                  orderedEquals(changed),
                  reason: 'Reduced-motion focus/hover must be immediate',
                );
                expect(calls.where((c) => c.method == 'action'), isEmpty);
                expect(calls.where((c) => c.method == 'painted'), hasLength(1));
                expect(t.takeException(), isNull);
              } finally {
                await mouse?.removePointer();
                await t.pumpWidget(const SizedBox());
                await t.pump();
                t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                  channel,
                  null,
                );
                t.view.reset();
              }
            },
          );
        }
      }
    }
  }
}
