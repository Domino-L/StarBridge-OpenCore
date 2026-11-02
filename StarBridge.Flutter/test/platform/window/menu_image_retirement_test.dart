import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/menu_image_retirement.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_window_lifetime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('starbridge/test-image-retirement');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  testWidgets(
    'timeout and its late positive receipt never replay the resource operation',
    (t) async {
      final reply = Completer<Object?>();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return reply.future;
      });
      final owner = MenuImageRetirement(
        MenuWindowLifetime(),
        channel,
        isCurrent: () => true,
        request: () => 7,
      );
      owner.beginImageMaintenance();
      owner.endImageMaintenance();
      final completion = expectLater(
        owner.imageMaintenanceSettled,
        throwsA(isA<TimeoutException>()),
      );
      await t.pump();
      await t.pump(const Duration(seconds: 4));
      await completion;
      expect(calls, hasLength(2));
      reply.complete({
        'schemaVersion': 1,
        'resourceEpoch': 2,
        'enginePresent': true,
      });
      await t.pump();
      expect(calls, hasLength(2));
    },
  );
  test('a retired owner cannot send control to a replacement; future snapshots still see the new epoch', () async {
    var current = false;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {
        'schemaVersion': 1,
        'resourceEpoch': (call.arguments as Map)['resourceEpoch'],
        'enginePresent': false,
      };
    });
    final lifetime = MenuWindowLifetime();
    final owner = MenuImageRetirement(
      lifetime,
      channel,
      isCurrent: () => current,
      request: () => 7,
    );
    owner.beginImageMaintenance();
    owner.endImageMaintenance();
    await owner.imageMaintenanceSettled;
    expect(calls, isEmpty);
    expect(lifetime.imageEpoch, 2);
    current = true;
    owner.beginImageMaintenance();
    owner.endImageMaintenance();
    await owner.imageMaintenanceSettled;
    expect(calls, hasLength(2));
    expect((calls.first.arguments as Map)['resourceEpoch'], 3);
    expect((calls.last.arguments as Map)['resourceEpoch'], 4);
  });
}
