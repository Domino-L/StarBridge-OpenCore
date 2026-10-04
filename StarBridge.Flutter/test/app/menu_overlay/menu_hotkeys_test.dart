import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/window/bridge_menu_hotkeys.dart';
import 'package:starbridge_flutter/platform/window/menu_hotkey_port.dart';
import 'package:starbridge_flutter/platform/window/menu_shortcut_settings.dart';
import 'package:starbridge_flutter/platform/window/menu_preview_window_port.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';

class _Hotkeys implements MenuHotkeyPort, MenuShortcutSettingsPort {
  late Future<void> Function(MenuHotkeyIntent) trigger;
  late void Function() revoke;
  final phases = <(int, String, int)>[];
  int? client;
  bool disposed = false;
  MenuShortcutSettings settings = const MenuShortcutSettings(
    3,
    'F8',
    true,
    true,
    'registered',
  );
  Completer<MenuShortcutSettings>? pendingSettings;
  int settingsWrites = 0;
  @override
  Future<MenuShortcutSettings> readShortcut() async =>
      pendingSettings == null ? settings : await pendingSettings!.future;
  @override
  Future<MenuShortcutSettings> saveShortcut(MenuShortcutSettings value) async {
    settingsWrites++;
    return settings = MenuShortcutSettings(
      value.revision + 1,
      value.binding,
      value.enabled,
      value.closeWithHotkey,
      value.enabled ? 'registered' : 'disabled',
    );
  }

  @override
  void initialize(
    int Function() nextClient,
    Future<void> Function(MenuHotkeyIntent) onIntent,
    void Function() onRevoked,
  ) {
    client = nextClient();
    trigger = onIntent;
    revoke = onRevoked;
  }

  @override
  Future<void> window(int request, String phase, int handle) async =>
      phases.add((request, phase, handle));
  @override
  void dispose() {
    disposed = true;
  }
}

class _Friends implements MenuFriendsReadLease {
  @override
  void show(bool visible) {}
  @override
  void dispose() {}
}

class _PendingPreferences implements MenuWindowPreferencesPort {
  final result = Completer<MenuWindowPreferences>();
  @override
  Future<MenuWindowPreferences> read() => result.future;
  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences value) async =>
      value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('starbridge/menu-primary');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Future<void> state(int request, String state) =>
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('state', {
            'request': request,
            'state': state,
            'window': 77,
          }),
        ),
        (_) {},
      );
  MenuOpenLabels labels() =>
      (contextLabel: 'Menu', returnLabel: 'Return', settingsLabel: 'Settings');
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<Object?> incoming(String method, Object? args) async {
    final result = Completer<Object?>();
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (data) {
        try {
          result.complete(const StandardMethodCodec().decodeEnvelope(data!));
        } on Object catch (error, stack) {
          result.completeError(error, stack);
        }
      },
    );
    return result.future;
  }

  testWidgets(
    'menu settings delegate to the same primary port and reject hidden/stale openings',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'preview' ? 7 : null;
      });
      final keys = _Hotkeys();
      final window = MethodChannelMenuPreviewWindow(
        lifetime: MenuWindowLifetime(),
        friends: (_) => _Friends(),
        hotkeys: keys,
        hotkeyLabels: labels,
      );
      window.initialize();
      final opening = window.openLive(
        contextLabel: 'Menu',
        returnLabel: 'Return',
        settingsLabel: 'Settings',
      );
      await tester.pump();
      final request =
          (calls.singleWhere((c) => c.method == 'preview').arguments
                  as Map)['request']
              as int;
      expect((calls.last.arguments as Map)['shortcutSettings'], true);
      await state(request, 'visible');
      expect(await opening, true);
      final read = jsonDecode(
        await incoming('shortcutSettings', {'opening': 7, 'action': 'get'})
            as String,
      );
      expect(read['binding'], 'F8');
      final next = const MenuShortcutSettings(
        3,
        'F10',
        false,
        false,
        'disabled',
      );
      await incoming('shortcutSettings', {
        'opening': 7,
        'action': 'update',
        'payload': jsonEncode(next.toMap()),
      });
      expect((await window.shortcutSettings!.readShortcut()).binding, 'F10');
      expect(keys.settingsWrites, 1);
      await expectLater(
        incoming('shortcutSettings', {
          'opening': 6,
          'action': 'update',
          'payload': jsonEncode(next.toMap()),
        }),
        throwsA(isA<PlatformException>()),
      );
      expect(keys.settingsWrites, 1);
      keys.pendingSettings = Completer<MenuShortcutSettings>();
      final late = incoming('shortcutSettings', {
        'opening': 7,
        'action': 'get',
      });
      final rejected = expectLater(
        late,
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'menuHotkey.session_unavailable',
          ),
        ),
      );
      await tester.pump();
      await state(request, 'hidden');
      keys.pendingSettings!.complete(keys.settings);
      await rejected;
      window.dispose();
      await tester.pump();
    },
  );

  for (final revokeDuringRead in [false, true]) {
    test(
      'shortcut settings use scoped bridge and reject revoked replies: $revokeDuringRead',
      () async {
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 1,
        );
        final active = ValueNotifier(true), requests = <BridgeEnvelope>[];
        final release = Completer<void>();
        final subscription = pair.host.incoming.listen((request) async {
          requests.add(request);
          if (request.name == 'menuHotkey.settings.get' && revokeDuringRead) {
            await release.future;
          }
          await pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: request.sessionGeneration,
              status: 'ok',
              payload: request.name.startsWith('menuHotkey.settings.')
                  ? {
                      'schemaVersion': 1,
                      'revision': 8,
                      'binding': 'F8',
                      'enabled': true,
                      'closeWithHotkey': false,
                      'state': 'registered',
                    }
                  : {'schemaVersion': 1, 'state': 'registered'},
            ),
          );
        });
        final bridge = BridgeMenuHotkeys(
          session,
          activation: active,
          isActive: () => active.value,
        );
        bridge.initialize(() => 1, (_) async {}, () {});
        final read = bridge.readShortcut();
        if (revokeDuringRead) {
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
          await _wait(
            () => requests.any((r) => r.name == 'menuHotkey.settings.get'),
          );
          active.value = false;
          release.complete();
          await rejected;
        } else {
          expect((await read).binding, 'F8');
          await bridge.saveShortcut(
            const MenuShortcutSettings(8, 'F9', false, false, 'disabled'),
          );
          final write = requests.singleWhere(
            (r) => r.name == 'menuHotkey.settings.update',
          );
          expect(write.payload, {
            'schemaVersion': 1,
            'client': 1,
            'expectedRevision': 8,
            'binding': 'F9',
            'enabled': false,
            'closeWithHotkey': false,
          });
        }
        bridge.dispose();
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();
        await session.close();
        await pair.host.close();
        active.dispose();
      },
    );
  }

  test(
    'a late attach acknowledgement cannot restore revoked shortcut authority',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      );
      final active = ValueNotifier(true), requests = <BridgeEnvelope>[];
      final releaseFirst = Completer<void>();
      final subscription = pair.host.incoming.listen((request) async {
        requests.add(request);
        if (request.name == 'menuHotkey.attach' &&
            request.payload['client'] == 1) {
          await releaseFirst.future;
        }
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            status: 'ok',
            payload: const {'schemaVersion': 1, 'state': 'registered'},
          ),
        );
      });
      final bridge = BridgeMenuHotkeys(
        session,
        activation: active,
        isActive: () => active.value,
      );
      var client = 0, revoked = 0;
      bridge.initialize(() => ++client, (_) async {}, () => revoked++);
      await _wait(() => requests.isNotEmpty);
      active.value = false;
      active.value = true;
      expect(revoked, 1);
      releaseFirst.complete();
      await _wait(
        () => requests.where((r) => r.name == 'menuHotkey.attach').length == 2,
      );
      await bridge.window(40, 'opening', 0);
      expect(
        requests
            .where((r) => r.name == 'menuHotkey.detach')
            .single
            .payload['client'],
        1,
      );
      expect(requests.last.payload['client'], 2);
      bridge.dispose();
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      await session.close();
      await pair.host.close();
      active.dispose();
    },
  );

  testWidgets(
    'hotkey opens through the scoped live request and close cannot target an older request',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'preview' ? 7 : null;
      });
      final keys = _Hotkeys();
      final window = MethodChannelMenuPreviewWindow(
        lifetime: MenuWindowLifetime(),
        friends: (_) => _Friends(),
        hotkeys: keys,
        hotkeyLabels: labels,
      );
      window.initialize();
      final opening = keys.trigger(const MenuHotkeyIntent('open', 0, 44, 66));
      await tester.pump();
      final payload =
          calls.singleWhere((c) => c.method == 'preview').arguments as Map;
      final request = payload['request'] as int;
      expect(request, greaterThan(keys.client!));
      expect(payload['liveFriends'], true);
      expect(payload['targetWindow'], 44);
      expect(payload['targetProcessId'], 66);
      expect(keys.phases.first, (request, 'opening', 0));
      await state(request, 'visible');
      await opening;
      await tester.pump();
      expect(keys.phases.last, (request, 'visible', 77));
      await keys.trigger(MenuHotkeyIntent('close', request - 1, 0, 0));
      expect(calls.where((c) => c.method == 'close'), isEmpty);
      await keys.trigger(MenuHotkeyIntent('close', request, 0, 0));
      expect((calls.last.arguments as Map)['request'], request);
      await state(request, 'hidden');
      await tester.pump();
      expect(keys.phases.last, (request, 'closed', 0));
      window.dispose();
      expect(keys.disposed, true);
      await tester.pump();
    },
  );

  testWidgets(
    'account revocation while reading preferences cannot reopen native menu',
    (tester) async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      final preferences = _PendingPreferences(), keys = _Hotkeys();
      final window = MethodChannelMenuPreviewWindow(
        lifetime: MenuWindowLifetime(),
        friends: (_) => _Friends(),
        preferences: preferences,
        hotkeys: keys,
        hotkeyLabels: labels,
      );
      window.initialize();
      final opening = keys.trigger(const MenuHotkeyIntent('open', 0, 44, 66));
      await tester.pump();
      keys.revoke();
      preferences.result.complete(MenuWindowPreferences.defaults);
      await opening;
      expect(calls.where((c) => c.method == 'preview'), isEmpty);
      window.dispose();
      await tester.pump();
    },
  );

  test('Host event subscription ignores old clients and revokes immediately on logout', () async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    final active = ValueNotifier(false),
        requests = <BridgeEnvelope>[],
        received = <MenuHotkeyIntent>[];
    final subscription = pair.host.incoming.listen((request) async {
      requests.add(request);
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: 'ok',
          payload: const {'schemaVersion': 1, 'state': 'registered'},
        ),
      );
    });
    final bridge = BridgeMenuHotkeys(
      session,
      activation: active,
      isActive: () => active.value,
    );
    var client = 0, revoked = 0, sequence = 100;
    bridge.initialize(
      () => ++client,
      (intent) async => received.add(intent),
      () => revoked++,
    );
    await Future<void>.delayed(Duration.zero);
    expect(requests, isEmpty);
    active.value = true;
    await _wait(() => requests.any((r) => r.name == 'menuHotkey.attach'));
    await bridge.window(10, 'opening', 0); // waits for attach ack
    Future<void> send(int id) => pair.host.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'menuHotkey.intent',
        sessionGeneration: 1,
        sequence: ++sequence,
        payload: {
          'schemaVersion': 1,
          'client': id,
          'action': 'open',
          'request': 0,
          'targetWindow': 44,
          'targetProcessId': 66,
        },
      ),
    );
    await send(99);
    await send(client);
    await _wait(() => received.length == 1);
    expect(received.single.targetWindow, 44);
    active.value = false;
    expect(revoked, 1);
    await send(client);
    await _wait(() => requests.any((r) => r.name == 'menuHotkey.detach'));
    expect(received.length, 1);
    active.value = true;
    await _wait(
      () => requests.where((r) => r.name == 'menuHotkey.attach').length == 2,
    );
    await bridge.window(20, 'opening', 0);
    await send(1);
    await send(2);
    await _wait(() => received.length == 2);
    bridge.dispose();
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    await session.close();
    await pair.host.close();
    active.dispose();
  });
}

Future<void> _wait(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Expected menu state did not arrive');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}
