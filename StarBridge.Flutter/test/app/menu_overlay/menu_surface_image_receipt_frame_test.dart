import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_surface_app.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_surface_features.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';

void main() {
  test('channel-only organization projection retires its logo without touching peer portraits', () {
    const image =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==';
    final view = MenuFeatureView.parse({
      'state': 'ready',
      'scope': 'retained',
      'channels': [
        {
          'title': 'Channel',
          'detail': 'Retained',
          'avatar': image,
          'buttons': <Object?>[],
        },
      ],
    });
    expect(view.state, 'ready');
    expect(view.organization, isNull);
    final views = {'organizations': view, 'comms': view};
    final owner = MenuSurfaceFeatures(
      features: views,
      revisions: {},
      visible: {},
      timers: {},
      opening: () => 1,
      wanted: () => true,
      enabled: () => true,
      update: (action) => action(),
    );
    owner.retire({'schemaVersion': 1, 'resourceEpoch': 2});
    expect(views['organizations']!.channels.single.avatar, isNull);
    expect(views['organizations']!.scope, 'retained');
    expect(views['comms']!.channels.single.avatar, image);
    expect(
      owner.retire({'schemaVersion': 1, 'resourceEpoch': 1})['resourceEpoch'],
      2,
    );
  });
  testWidgets('surface receipt waits for the retirement frame', (t) async {
    const channel = MethodChannel('starbridge/menu-surface');
    final messenger = t.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await t.pumpWidget(const MenuOverlaySurfaceApp(workspacePreview: true));
    await t.pump();
    final receipt = Completer<ByteData?>();
    final call = messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('imageMaintenance', {
          'schemaVersion': 1,
          'resourceEpoch': 1,
        }),
      ),
      receipt.complete,
    );
    await t.idle();
    expect(
      receipt.isCompleted,
      isFalse,
      reason: 'A DTO update is not yet the frame that releases image widgets.',
    );
    await t.pump();
    await call;
    expect(
      const StandardMethodCodec().decodeEnvelope((await receipt.future)!),
      {'schemaVersion': 1, 'resourceEpoch': 1},
    );
    await t.pumpWidget(const SizedBox.shrink());
  });
}
