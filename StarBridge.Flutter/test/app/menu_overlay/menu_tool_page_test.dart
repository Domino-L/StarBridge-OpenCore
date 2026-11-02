import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_tool_page.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/app/runtime/menu_tool_page_navigation.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';

import 'menu_preview_window_test.dart' show Lease;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'primary opens the overlay page for the visible opening without the hangar capability',
    (tester) async {
      const primary = MethodChannel('starbridge/menu-primary');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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
      addTearDown(() => messenger.setMockMethodCallHandler(primary, null));
      final lifetime = MenuWindowLifetime();
      final navigation = ValueNotifier<OpenDestinationIntent?>(null);
      final routes = <String>[];
      navigation.addListener(() => routes.add(navigation.value!.route));
      final unbind = bindMenuToolPages(lifetime, navigation);
      // No execHangarProvider: the overlay page must not need that flag.
      final window = MethodChannelMenuPreviewWindow(
        lifetime: lifetime,
        friends: (_) => Lease(),
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

      expect(await incoming('openHudSettings', {'opening': 7}), true);
      expect(await incoming('openHudSettings', {'opening': 7}), true);
      expect(routes, ['/overlay', '/overlay']);
      await expectLater(
        incoming('openExecHangar', {'opening': 7}),
        throwsA(isA<PlatformException>()),
      );
      for (final args in [
        null,
        {'opening': 6},
        {'opening': 7, 'route': '/settings/privacy'},
        {'opening': '7'},
      ]) {
        await expectLater(
          incoming('openHudSettings', args),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'menuToolPage.session_unavailable',
            ),
          ),
        );
      }
      await incoming('state', {'request': request, 'state': 'hidden'});
      await expectLater(
        incoming('openHudSettings', {'opening': 7}),
        throwsA(isA<PlatformException>()),
      );
      expect(lifetime.toolPages.hudSettings.value, 2);

      unbind();
      lifetime.toolPages.hudSettings.value++;
      expect(routes, hasLength(2));
      window.dispose();
      navigation.dispose();
      await tester.pump();
    },
  );

  test('opener sends only the current opening and reports refusals', () async {
    const channel = MethodChannel('starbridge/test-tool-page-opener');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    Object? reply = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (reply is PlatformException) throw reply;
      return reply;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    int? opening = 4;
    final opener = MenuToolPageOpener(channel, () => opening);

    expect(await opener.openHudSettings(), true);
    expect(calls.single.method, 'openHudSettings');
    expect(calls.single.arguments, {'opening': 4});
    reply = PlatformException(code: 'menuToolPage.session_unavailable');
    expect(await opener.openHudSettings(), false);
    reply = false;
    expect(await opener.openHudSettings(), false);
    opening = null;
    expect(await opener.openHudSettings(), false);
    opening = -1;
    expect(await opener.openHudSettings(), false);
    expect(calls, hasLength(3));
  });
}
