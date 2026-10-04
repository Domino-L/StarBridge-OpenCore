import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/menu_screenshot_destination_request.dart';
import 'package:starbridge_flutter/platform/window/menu_screenshot_directory.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';

import 'menu_preview_window_test.dart' show Lease;
import '../../features/overlay_settings/menu_screenshot_directory_settings_test.dart'
    show DirectoryPort;

class PendingDirectory extends DirectoryPort {
  var completer = Completer<MenuScreenshotDirectory>();
  @override
  Future<MenuScreenshotDirectory> read() {
    calls.add('read');
    return completer.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final args in [
    null,
    {},
    {'opening': 1.0},
    {'opening': 2},
    {'opening': 1, 'directory': r'C:\forbidden'},
  ]) {
    test(
      'trusted request rejects invalid shape or opening $args before read',
      () async {
        final port = DirectoryPort();
        await expectLater(
          MenuScreenshotDestinationRequest.handle(
            arguments: args,
            opening: 1,
            isCurrent: () => true,
            port: port,
          ),
          throwsA(isA<PlatformException>()),
        );
        expect(port.calls, isEmpty);
      },
    );
  }
  test('trusted read rejects absent capability and owner retirement before or after await', () async {
    for (final current in [false, true]) {
      await expectLater(
        MenuScreenshotDestinationRequest.handle(
          arguments: {'opening': 1},
          opening: 1,
          isCurrent: () => current,
          port: null,
        ),
        throwsA(isA<PlatformException>()),
      );
    }
    final port = PendingDirectory();
    var current = true;
    final work = MenuScreenshotDestinationRequest.handle(
      arguments: {'opening': 1},
      opening: 1,
      isCurrent: () => current,
      port: port,
    );
    current = false;
    port.completer.complete(port.value);
    await expectLater(
      work,
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'menu.closed'),
      ),
    );
  });
  testWidgets(
    'production primary channel advertises only bool and reads current destination for native; hidden late result denied',
    (tester) async {
      const channel = MethodChannel('starbridge/menu-primary');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      int? request;
      Map? payload;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'preview') {
          payload = call.arguments as Map;
          request = payload!['request'];
          return 7;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      Future<Object?> incoming(String name, Map args) async {
        final result = Completer<Object?>();
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall(name, args)),
          (bytes) {
            try {
              result.complete(
                bytes == null
                    ? null
                    : const StandardMethodCodec().decodeEnvelope(bytes),
              );
            } on Object catch (error) {
              result.completeError(error);
            }
          },
        );
        return result.future;
      }

      final port = PendingDirectory();
      final window = MethodChannelMenuPreviewWindow(
        lifetime: MenuWindowLifetime(),
        friends: (_) => Lease(),
        screenshotDirectory: port,
      );
      final opened = window.openLive(
        contextLabel: 'Menu',
        returnLabel: 'Return',
        settingsLabel: 'Settings',
      );
      await tester.pump();
      await incoming('state', {'request': request, 'state': 'visible'});
      expect(await opened, true);
      expect(payload!['screenshotDirectory'], true);
      expect(payload!.values, isNot(contains(port.value.directory)));
      final confirmed = incoming('screenshotDestination', {'opening': 7});
      await tester.pump();
      expect(port.calls, ['read']);
      port.completer.complete(port.value);
      expect(await confirmed, port.value.directory);
      port.completer = Completer<MenuScreenshotDirectory>();
      final value = incoming('screenshotDestination', {'opening': 7});
      await tester.pump();
      expect(port.calls, ['read', 'read']);
      await incoming('state', {'request': request, 'state': 'hidden'});
      port.completer.complete(port.value);
      await expectLater(
        value,
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'menu.closed'),
        ),
      );
      window.dispose();
      await tester.pump();
    },
  );
}
