import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/menu_browser_resume.dart';
import 'package:starbridge_flutter/platform/window/menu_browser_resume_request.dart';
import 'package:starbridge_flutter/platform/window/surface_menu_browser_resume.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';

import 'menu_preview_window_test.dart' show Lease;
import '../../features/overlay_settings/menu_browser_resume_settings_test.dart'
    show MemoryBrowserResume;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('primary handler rejects identity, paths, malformed intents before touching storage', () async {
    final store = MemoryBrowserResume();
    Future<String> call(Object? arguments) => MenuBrowserResumeRequest.handle(
      arguments: arguments,
      opening: 7,
      isCurrent: () => true,
      port: store,
    );
    for (final args in [
      null,
      {},
      {'opening': 6, 'action': 'get'},
      {'opening': 7, 'action': 'get', 'ownerKey': 'other'},
      {'opening': 7, 'action': 'update', 'payload': '{}'},
      {
        'opening': 7,
        'action': 'update',
        'payload': '{"revision":0,"enabled":"true"}',
      },
      {
        'opening': 7,
        'action': 'update',
        'payload':
            '{"revision":0,"enabled":true,"url":"https://example.invalid"}',
      },
      {
        'opening': 7,
        'action': 'remember',
        'payload': '{"revision":0,"url":"file:///c:/private"}',
      },
      {
        'opening': 7,
        'action': 'remember',
        'payload':
            '{"revision":0,"url":"https://user:password@example.invalid"}',
      },
      {'opening': 7, 'action': 'script', 'payload': '{}'},
    ]) {
      await expectLater(call(args), throwsA(isA<PlatformException>()));
    }
    expect(store.reads, 0);
    expect(store.updates, 0);
    expect(store.writes, isEmpty);
    final read = MenuBrowserResume.parse(
      jsonDecode(await call({'opening': 7, 'action': 'get'})),
    );
    expect(read.enabled, false);
    expect(read.url, isNull);
  });
  testWidgets(
    'surface delegates exact bounded intents to primary and loses authority when hidden',
    (tester) async {
      const primary = MethodChannel('starbridge/menu-primary'),
          surface = MethodChannel('starbridge/test-resume-surface');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final sent = <MethodCall>[], store = MemoryBrowserResume();
      int request = 0;
      Future<Object?> incoming(String method, Object? args) async {
        final result = Completer<Object?>();
        await messenger.handlePlatformMessage(
          primary.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (data) {
            try {
              result.complete(
                const StandardMethodCodec().decodeEnvelope(data!),
              );
            } on Object catch (e, st) {
              result.completeError(e, st);
            }
          },
        );
        return result.future;
      }

      messenger.setMockMethodCallHandler(primary, (call) async {
        if (call.method == 'preview') {
          request = (call.arguments as Map)['request'];
          return 7;
        }
        return null;
      });
      messenger.setMockMethodCallHandler(surface, (call) {
        sent.add(call);
        return incoming(call.method, call.arguments);
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(primary, null);
        messenger.setMockMethodCallHandler(surface, null);
      });
      final window = MethodChannelMenuPreviewWindow(
        lifetime: MenuWindowLifetime(),
        friends: (_) => Lease(),
        browserResume: store,
      );
      final open = window.openLive(
        contextLabel: 'Menu',
        returnLabel: 'Return',
        settingsLabel: 'Settings',
      );
      await tester.pump();
      await incoming('state', {
        'request': request,
        'state': 'visible',
        'window': 77,
      });
      expect(await open, true);
      var current = true;
      final adapter = SurfaceMenuBrowserResume(surface, 7, () => current);
      final read = await adapter.read();
      final enabled = await adapter.setEnabled(read, true);
      await adapter.remember(enabled, 'https://example.invalid/a');
      expect(store.writes, ['https://example.invalid/a']);
      expect(sent.every((call) => call.method == 'browserResume'), true);
      final update = sent[1].arguments as Map;
      expect(jsonDecode(update['payload']), {'revision': 0, 'enabled': true});
      expect(update.keys.toSet(), {'opening', 'action', 'payload'});
      await expectLater(
        incoming('browserResume', {'opening': 6, 'action': 'get'}),
        throwsA(isA<PlatformException>()),
      );
      final pending = Completer<MenuBrowserResume>();
      store.pendingRead = pending;
      final late = adapter.read();
      final rejected = expectLater(late, throwsA(anything));
      await tester.pump();
      await incoming('state', {'request': request, 'state': 'hidden'});
      current = false;
      pending.complete(
        const MenuBrowserResume(1, true, 'https://example.invalid/old'),
      );
      await rejected;
      final reads = store.reads;
      await expectLater(adapter.read(), throwsA(anything));
      expect(store.reads, reads);
      window.dispose();
      await tester.pump();
    },
  );
}
