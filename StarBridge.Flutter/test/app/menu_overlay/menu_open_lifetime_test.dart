import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/menu_preview_window_port.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';

class _PendingPreferences implements MenuWindowPreferencesPort {
  final readResult = Completer<MenuWindowPreferences>();
  @override
  Future<MenuWindowPreferences> read() => readResult.future;
  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences value) async =>
      value;
}

class _Lease implements MenuFriendsReadLease {
  final visibility = <bool>[];
  @override
  void show(bool visible) => visibility.add(visible);
  @override
  void dispose() {}
}

void main() {
  final lifetime = MenuWindowLifetime();
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('starbridge/menu-primary');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  int? request;
  void mock(Future<Object?> Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      if (call.method == 'preview') {
        request = (call.arguments as Map)['request'] as int;
      }
      return handler(call);
    });
  }

  Future<void> event(String method, Object? args) =>
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(
            method,
            method == 'state' && args is String
                ? {'request': request, 'state': args}
                : args,
          ),
        ),
        (_) {},
      );
  Future<bool> open(MethodChannelMenuPreviewWindow window) => window.openLive(
    contextLabel: 'Context',
    returnLabel: 'Return',
    settingsLabel: 'Settings',
  );
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets(
    'disposing previous owner leaves the next account handler attached',
    (tester) async {
      final calls = <MethodCall>[];
      mock((call) async {
        calls.add(call);
        return call.method == 'preview' ? 7 : null;
      });
      final old = MethodChannelMenuPreviewWindow(
        lifetime: lifetime,
        friends: (_) => _Lease(),
      );
      final first = open(old);
      await tester.pump();
      final oldRequest = request;
      await event('state', 'visible');
      expect(await first, true);
      final next = MethodChannelMenuPreviewWindow(
        lifetime: lifetime,
        friends: (_) => _Lease(),
      );
      final second = open(next);
      await tester.pump();
      expect(request, isNot(oldRequest));
      old.dispose();
      await tester.pump();
      expect((calls.last.arguments as Map)['request'], oldRequest);
      await event('state', {'request': oldRequest, 'state': 'hidden'});
      await event('state', 'visible');
      expect(await second, true);
      next.dispose();
      await tester.pump();
    },
  );

  testWidgets(
    'reopen ignores previous hidden and visible events before reply',
    (tester) async {
      final reply = Completer<int>();
      var count = 0;
      mock((call) async {
        if (call.method != 'preview') return null;
        return ++count == 1 ? 7 : reply.future;
      });
      final window = MethodChannelMenuPreviewWindow(
        lifetime: lifetime,
        friends: (_) => _Lease(),
      );
      final first = open(window);
      await tester.pump();
      final oldRequest = request;
      await event('state', 'visible');
      expect(await first, true);
      final second = open(window);
      var completed = false;
      second.then((_) => completed = true);
      await tester.pump();
      await event('state', {'request': oldRequest, 'state': 'hidden'});
      await event('state', {'request': oldRequest, 'state': 'visible'});
      reply.complete(8);
      await tester.pump();
      expect(completed, false);
      await event('state', 'visible');
      expect(await second, true);
      window.dispose();
      await tester.pump();
    },
  );

  testWidgets('timeout close is scoped to the native open request', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    mock((call) async {
      calls.add(call);
      return call.method == 'preview' ? 7 : null;
    });
    final window = MethodChannelMenuPreviewWindow(
      lifetime: lifetime,
      friends: (_) => _Lease(),
    );
    final result = open(window);
    await tester.pump();
    await tester.pump(const Duration(seconds: 7));
    expect(await result, false);
    final close = calls.singleWhere((call) => call.method == 'close');
    expect(close.arguments, {
      'request': (calls.first.arguments as Map)['request'],
    });
    window.dispose();
    await tester.pump();
  });

  testWidgets('detached account never opens after pending preference read', (
    tester,
  ) async {
    final store = _PendingPreferences();
    final calls = <String>[];
    mock((call) async {
      calls.add(call.method);
      return call.method == 'preview' ? 7 : null;
    });
    final window = MethodChannelMenuPreviewWindow(
      lifetime: lifetime,
      preferences: store,
      friends: (_) => _Lease(),
    );
    final opening = open(window);
    await tester.pump();
    window.dispose();
    store.readResult.complete(MenuWindowPreferences.defaults);
    await tester.pump();
    expect(await opening, false);
    expect(calls, ['detach']);
  });

  testWidgets('old timed out request cannot close the next account menu', (
    tester,
  ) async {
    final pending = Completer<int>();
    final calls = <String>[];
    mock((call) async {
      calls.add(call.method);
      return call.method == 'preview' ? pending.future : null;
    });
    final window = MethodChannelMenuPreviewWindow(
      lifetime: lifetime,
      friends: (_) => _Lease(),
    );
    final opening = open(window);
    await tester.pump();
    window.dispose();
    await tester.pump(const Duration(seconds: 7));
    expect(await opening, false);
    expect(calls, ['preview', 'detach']);
    pending.complete(7);
    await tester.pump();
  });

  testWidgets('hidden before native reply cannot reactivate feature leases', (
    tester,
  ) async {
    final pending = Completer<int>();
    final lease = _Lease();
    mock((call) async => call.method == 'preview' ? pending.future : null);
    final window = MethodChannelMenuPreviewWindow(
      lifetime: lifetime,
      friends: (_) => lease,
    );
    final opening = open(window);
    await tester.pump();
    await event('state', 'hidden');
    pending.complete(7);
    await tester.pump();
    expect(await opening, false);
    await event('friendsVisible', {'opening': 7, 'visible': true});
    expect(lease.visibility, isEmpty);
    window.dispose();
    await tester.pump();
  });

  testWidgets('display timeout clears opening even if close has no callback', (
    tester,
  ) async {
    final lease = _Lease();
    mock((call) async => call.method == 'preview' ? 7 : null);
    final window = MethodChannelMenuPreviewWindow(
      lifetime: lifetime,
      friends: (_) => lease,
    );
    final opening = open(window);
    await tester.pump();
    await event('friendsVisible', {'opening': 7, 'visible': true});
    await tester.pump(const Duration(seconds: 7));
    expect(await opening, false);
    expect(lease.visibility.last, false);
    await event('friendsVisible', {'opening': 7, 'visible': true});
    expect(lease.visibility.last, false);
    window.dispose();
    await tester.pump();
  });
}
