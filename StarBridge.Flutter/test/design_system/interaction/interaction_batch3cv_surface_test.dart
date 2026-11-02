import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_surface_app.dart';
import 'package:starbridge_flutter/platform/window/menu_interaction_presentation.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/menu_overlay/menu_overlay_surface_app_test.dart'
    show channel, snapshot, push;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show detach;
import 'interaction_batch3cm_bridge_test.dart' show incoming;
import 'interaction_batch3cv_test.dart' show roomFixture, activate;
import 'interaction_batch3cv_visual_test.dart' show showChat;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final id in ['menu-room-refresh', 'menu-room-message-refresh']) {
        testWidgets(
          '$suite $source $id actual auxiliary transport keeps the original refresh map',
          (t) async {
            t.view.devicePixelRatio = 1;
            t.view.physicalSize = const Size(1600, 1100);
            final semantics = t.ensureSemantics();
            final (_, primary) = await roomFixture(t);
            final calls = <MethodCall>[];
            final messenger = t.binding.defaultBinaryMessenger;
            messenger.setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return call.method == 'ready' ? snapshot(0, wanted: false) : null;
            });
            try {
              await t.pumpWidget(
                const MenuOverlaySurfaceApp(workspacePreview: true),
              );
              await push(t, {
                ...snapshot(7),
                'liveFeatures': true,
                'interactionPresentation': MenuInteractionPresentation(
                  style: MenuInteractionStyle.values.byName(suite.name),
                ).encode(),
              });
              await t.pumpAndSettle();
              await t.tap(find.byKey(const ValueKey('menu-tool-room')));
              await t.pump();
              await t.pump();
              expect(
                calls.where(
                  (call) =>
                      call.method == 'featureVisible' &&
                      (call.arguments as Map)['tool'] == 'rooms' &&
                      (call.arguments as Map)['visible'] == true,
                ),
                hasLength(1),
              );
              await incoming(channel, 'featureView', {
                'opening': 7,
                'revision': 1,
                'payload': jsonEncode({
                  'tool': 'rooms',
                  ...primary.currentView,
                }),
              });
              await t.pumpAndSettle();
              if (id == 'menu-room-message-refresh') await showChat(t);
              await activate(t, source, find.byKey(Key(id)));
              await t.pump();
              await t.pump();
              final request = calls
                  .where((call) => call.method == 'featureAction')
                  .single;
              expect(request.arguments, {
                'opening': 7,
                'tool': 'rooms',
                'key': 'refresh',
                'value': '',
                'motionSource': source == 'pointer' ? 'pointer' : 'keyboard',
              });
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
              await detach(t);
              primary.dispose();
              messenger.setMockMethodCallHandler(channel, null);
              await t.pump();
              t.view.reset();
            }
          },
        );
      }
    }
  }
}
