import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_surface_app.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';

import 'menu_overlay_surface_app_test.dart' show push, snapshot;
import 'menu_chat_media_test.dart' show photo;

void main() {
  const channel = MethodChannel('starbridge/menu-surface');
  testWidgets(
    'existing hidden tool retires cached organization images without reopening it or resetting metadata',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1280, 900);
      addTearDown(t.view.reset);
      final calls = <MethodCall>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      Future<void> event(String method, Map<String, Object?> args) async {
        final handled = t.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (_) {},
        );
        await t.pump();
        await handled;
      }

      await t.pumpWidget(const MenuOverlaySurfaceApp(workspacePreview: true));
      await t.pump();
      await push(t, {...snapshot(1), 'liveFeatures': true, 'resourceEpoch': 0});
      await t.pump();
      MenuBridgePreview view() =>
          t.widget<MenuBridgePreview>(find.byType(MenuBridgePreview));
      view().onFeatureVisible!('organizations', true);
      final payload = {
        'tool': 'organizations',
        'state': 'ready',
        'scope': 'same-scope',
        'title': 'Retained organization',
        'rows': <Object?>[],
        'organization': {
          'tab': 'directory',
          'total': 0,
          'matched': 0,
          'offset': 0,
          'rows': <Object?>[],
          'logo': photo,
        },
      };
      expect(MenuFeatureView.envelope(jsonEncode(payload)), isNotNull);
      await event('featureView', {
        'opening': 1,
        'revision': 1,
        'resourceEpoch': 0,
        'payload': jsonEncode(payload),
      });
      expect(view().features['organizations']!.organization!.logo, photo);
      view().onFeatureVisible!('organizations', false);
      await t.pump();
      expect(view().visible, isTrue);
      expect(view().features['organizations']!.organization!.logo, photo);
      calls.clear();
      await event('imageMaintenance', {'schemaVersion': 1, 'resourceEpoch': 1});
      final retained = view().features['organizations']!;
      expect(retained.organization!.logo == null, isTrue);
      expect(retained.scope, 'same-scope');
      expect(retained.title, 'Retained organization');
      expect(view().visible, isTrue);
      expect(calls, isEmpty);
      view().onFeatureVisible!('organizations', true);
      await event('featureView', {
        'opening': 1,
        'revision': 2,
        'resourceEpoch': 0,
        'payload': jsonEncode({
          ...payload,
          'title': 'New metadata, retired image',
        }),
      });
      expect(
        view().features['organizations']!.title,
        'New metadata, retired image',
      );
      expect(view().features['organizations']!.organization!.logo, isNull);
      await event('featureView', {
        'opening': 1,
        'revision': 3,
        'resourceEpoch': 1,
        'payload': jsonEncode({...payload, 'title': 'Current image'}),
      });
      expect(view().features['organizations']!.organization!.logo, photo);
      await push(t, snapshot(1, wanted: false));
      await t.pump();
      expect(view().visible, isFalse);
      expect(view().features, isEmpty);
      await t.pumpWidget(const SizedBox.shrink());
    },
  );
}
