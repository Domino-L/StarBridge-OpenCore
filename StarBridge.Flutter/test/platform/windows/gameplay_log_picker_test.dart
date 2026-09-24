import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/gameplay_log_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('starbridge/gameplay_files');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'requests pickGameLog without arguments and preserves the path',
    () async {
      const path = r'C:\Synthetic Logs\游戏\Game.log';
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return path;
      });

      expect(await pickGameplayLog(), path);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'pickGameLog');
      expect(calls.single.arguments, isNull);
    },
  );

  test('returns null when the native dialog is cancelled', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);

    expect(await pickGameplayLog(), isNull);
  });

  test(
    'propagates native errors with their code, message and details',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(
          code: 'gameplay_log_picker_failed',
          message: 'The Game.log file dialog failed.',
          details: 12291,
        );
      });

      await expectLater(
        pickGameplayLog(),
        throwsA(
          isA<PlatformException>()
              .having(
                (error) => error.code,
                'code',
                'gameplay_log_picker_failed',
              )
              .having(
                (error) => error.message,
                'message',
                'The Game.log file dialog failed.',
              )
              .having((error) => error.details, 'details', 12291),
        ),
      );
    },
  );

  test('propagates an unavailable platform implementation', () async {
    await expectLater(
      pickGameplayLog(),
      throwsA(isA<MissingPluginException>()),
    );
  });
}
