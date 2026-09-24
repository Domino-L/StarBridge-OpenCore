import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/method_channel_overlay_editor_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('starbridge/window-chrome');
  const window = MethodChannelOverlayEditorWindow();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'editor window uses native entry and exit without changing settings',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      await window.enter();
      await window.exit();
      expect(calls.map((call) => call.method), [
        'enterOverlayEditor',
        'exitOverlayEditor',
      ]);
      expect(calls.every((call) => call.arguments == null), isTrue);
    },
  );
  test('native errors reach the recoverable editor flow', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async =>
          throw PlatformException(code: 'overlay_editor_window_failed'),
    );
    await expectLater(window.enter(), throwsA(isA<PlatformException>()));
    await expectLater(window.exit(), throwsA(isA<PlatformException>()));
  });
}
