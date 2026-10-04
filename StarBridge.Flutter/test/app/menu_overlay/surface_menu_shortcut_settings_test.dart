import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/surface_menu_shortcut_settings.dart';
import 'package:starbridge_flutter/platform/window/menu_shortcut_settings.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fixture/menu-surface');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'surface preserves Host errors and refuses late session replies',
    () async {
      var current = true;
      final pending = Completer<String>();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if ((call.arguments as Map)['action'] == 'update') {
          throw PlatformException(code: 'menuPreferences.revision_conflict');
        }
        return pending.future;
      });
      final port = SurfaceMenuShortcutSettings(channel, 8, () => current);
      await expectLater(
        port.saveShortcut(
          const MenuShortcutSettings(3, 'F9', true, true, 'registered'),
        ),
        throwsA(
          isA<BridgeClientException>().having(
            (e) => e.code,
            'code',
            'menuPreferences.revision_conflict',
          ),
        ),
      );
      expect((calls.single.arguments as Map)['opening'], 8);
      final read = port.readShortcut();
      final rejected = expectLater(
        read,
        throwsA(
          isA<BridgeClientException>().having(
            (e) => e.code,
            'code',
            'menuHotkey.session_unavailable',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      current = false;
      pending.complete(
        jsonEncode(
          const MenuShortcutSettings(3, 'F9', true, true, 'registered').toMap(),
        ),
      );
      await rejected;
      final count = calls.length;
      await expectLater(
        port.readShortcut(),
        throwsA(isA<BridgeClientException>()),
      );
      expect(calls.length, count);
    },
  );
}
