import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_surface_app.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_surface_app_frame.dart';
import 'package:starbridge_flutter/platform/window/menu_interaction_presentation.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/menu_overlay/menu_overlay_surface_app_test.dart'
    show channel, snapshot, push;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show detach;
import 'interaction_batch3cw_test.dart' show fire;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final width in [400.0, 1200.0]) {
      for (final source in ['pointer', 'keyboard', 'reader', 'escape']) {
        testWidgets(
          '$suite $width $source actual fallback keeps dismiss protocol',
          (t) async {
            t.view.devicePixelRatio = 1;
            t.view.physicalSize = Size(width, 800);
            final semantics = t.ensureSemantics();
            final calls = <MethodCall>[];
            final messenger = t.binding.defaultBinaryMessenger;
            messenger.setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return call.method == 'ready' ? snapshot(0, wanted: false) : null;
            });
            try {
              await t.pumpWidget(const MenuOverlaySurfaceApp());
              await push(t, {
                ...snapshot(7),
                'interactionPresentation': MenuInteractionPresentation(
                  style: MenuInteractionStyle.values.byName(suite.name),
                ).encode(),
              });
              await t.pumpAndSettle();
              expect(find.byType(MenuSurfaceFallback), findsOneWidget);
              if (source == 'escape') {
                await t.sendKeyEvent(LogicalKeyboardKey.escape);
              } else {
                await fire(
                  t,
                  source,
                  find.byKey(const ValueKey('menu-return')),
                  '返回游戏',
                );
              }
              await t.pump();
              await t.pump();
              final request = calls.where((c) => c.method == 'dismiss').single;
              expect(request.arguments, isNull);
              expect(
                calls.where((c) => c.method == 'preferencesChanged'),
                isEmpty,
              );
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
              await detach(t);
              messenger.setMockMethodCallHandler(channel, null);
              t.view.reset();
            }
          },
        );
      }
    }
  }
}
