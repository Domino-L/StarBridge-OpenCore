import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/menu_screenshot_directory.dart';
import 'package:starbridge_flutter/platform/window/menu_screenshot_directory_request.dart';
import 'package:starbridge_flutter/platform/window/surface_menu_screenshot_directory.dart';

import '../../features/overlay_settings/menu_screenshot_directory_settings_test.dart'
    show DirectoryPort;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('synthetic/screenshot-directory');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('settings surface sends only intent and revision; primary rereads trusted value', () async {
    final host = DirectoryPort();
    final request = MenuScreenshotDirectoryRequest(host);
    final sent = <Map>[];
    messenger.setMockMethodCallHandler(channel, (call) {
      expect(call.method, 'screenshotDirectory');
      sent.add(call.arguments as Map);
      return request.handle(
        arguments: call.arguments,
        opening: 5,
        isCurrent: () => true,
      );
    });
    final surface = SurfaceMenuScreenshotDirectory(channel, 5, () => true);
    var value = await surface.read();
    value = await surface.choose(value);
    expect(value.revision, 1);
    expect((await surface.open(value)).opened, true);
    value = await surface.reset(value);
    expect(value.isDefault, true);
    expect(host.calls, [
      'read',
      'read',
      'choose',
      'read',
      'open',
      'read',
      'reset',
    ]);
    expect(sent.first, {'opening': 5, 'action': 'read'});
    expect(sent.skip(1), [
      {'opening': 5, 'action': 'choose', 'revision': 0},
      {'opening': 5, 'action': 'open', 'revision': 1},
      {'opening': 5, 'action': 'reset', 'revision': 1},
    ]);
  });

  test('invalid intents never read or mutate the Host', () async {
    final host = DirectoryPort();
    final request = MenuScreenshotDirectoryRequest(host);
    for (final args in [
      null,
      {},
      {'opening': 5.0, 'action': 'read'},
      {'opening': 4, 'action': 'read'},
      {'opening': 5, 'action': 'write', 'revision': 0},
      {'opening': 5, 'action': 'choose', 'revision': -1},
      {'opening': 5, 'action': 'choose', 'revision': 0.0},
      {'opening': 5, 'action': 'read', 'directory': r'C:\injected'},
      {
        'opening': 5,
        'action': 'choose',
        'revision': 0,
        'directory': r'C:\injected',
      },
    ]) {
      await expectLater(
        request.handle(arguments: args, opening: 5, isCurrent: () => true),
        throwsA(isA<PlatformException>()),
      );
    }
    expect(host.calls, isEmpty);
  });

  test('stale revision cannot choose or open another destination', () async {
    final host = DirectoryPort();
    final request = MenuScreenshotDirectoryRequest(host);
    for (final action in ['choose', 'reset', 'open']) {
      await expectLater(
        request.handle(
          arguments: {'opening': 5, 'action': action, 'revision': 3},
          opening: 5,
          isCurrent: () => true,
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'menuScreenshotDirectory.revision_conflict',
          ),
        ),
      );
    }
    expect(host.calls, ['read', 'read', 'read']);
  });

  test('hidden menu drops late chooser reply', () async {
    final host = DirectoryPort();
    final pending = Completer<MenuScreenshotDirectory>();
    host.pending = pending.future;
    var current = true;
    final request = MenuScreenshotDirectoryRequest(host);
    final work = request.handle(
      arguments: {'opening': 5, 'action': 'choose', 'revision': 0},
      opening: 5,
      isCurrent: () => current,
    );
    await Future<void>.delayed(Duration.zero);
    expect(host.calls, ['read', 'choose']);
    current = false;
    request.retire();
    pending.complete(host.value);
    await expectLater(work, throwsA(isA<PlatformException>()));
  });

  test(
    'surface rejects unexpected opened destination and late results',
    () async {
      final host = DirectoryPort();
      var current = true;
      final surface = SurfaceMenuScreenshotDirectory(channel, 5, () => current);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => jsonEncode({
          ...host.value.toMap(),
          'opened': true,
          'directory': r'C:\unexpected',
        }),
      );
      await expectLater(surface.open(host.value), throwsFormatException);
      messenger.setMockMethodCallHandler(channel, (_) async {
        current = false;
        return jsonEncode(host.value.toMap());
      });
      await expectLater(surface.read(), throwsA(isA<Exception>()));
    },
  );
}
