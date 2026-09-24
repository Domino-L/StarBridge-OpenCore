import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';
import 'package:starbridge_flutter/platform/window/menu_preview_window_port.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';

class MemoryMenuPreferences implements MenuWindowPreferencesPort {
  MenuWindowPreferences value = MenuWindowPreferences.defaults;
  final saved = <MenuWindowPreferences>[];
  @override
  Future<MenuWindowPreferences> read() async => value;
  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences next) async {
    if (next.revision != value.revision) throw StateError('revision conflict');
    saved.add(next);
    return value = MenuWindowPreferences(
      value.revision + 1,
      next.layout,
      next.settings,
    );
  }
}

class Lease implements MenuFriendsReadLease {
  final List<bool> visibility = [];
  bool disposed = false;
  @override
  void show(bool visible) => visibility.add(visible);
  @override
  void dispose() => disposed = true;
}

class ComposeLease implements MenuCommsReadLease, MenuCommsComposeLease {
  final calls = <String>[];
  @override
  void show(bool visible) {}
  @override
  void act(String action, String key) {}
  @override
  void dispose() {}
  @override
  void compose(String action, String key, String text, int revision) =>
      calls.add('$action/$key/$text/$revision');
}

class FriendActionLease extends Lease implements MenuFriendsActionLease {
  final actions = <String>[];
  @override
  void act(String action, String key, String value) =>
      actions.add('$action/$key/$value');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('starbridge/menu-primary');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Future<void> state(String value) => messenger.handlePlatformMessage(
    channel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall('state', value)),
    (_) {},
  );
  Future<bool> open(MethodChannelMenuPreviewWindow preview) => preview.open(
    contextLabel: 'Preview',
    returnLabel: 'Return',
    settingsLabel: 'Settings',
  );
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('demo preview cannot overwrite the remembered live desktop', (
    tester,
  ) async {
    final store = MemoryMenuPreferences();
    final window = MethodChannelMenuPreviewWindow(preferences: store);
    messenger.setMockMethodCallHandler(channel, (_) async => 8);
    final opening = open(window);
    await tester.pump();
    await state('visible');
    expect(await opening, true);
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('preferencesChanged', {
          'opening': 8,
          'payload': MenuWindowPreferences.defaults.encode(),
        }),
      ),
      (_) {},
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(store.saved, isEmpty);
    window.dispose();
    await tester.pump();
  });

  testWidgets(
    'last geometry is saved after immediate hide; stale opening cannot overwrite it',
    (tester) async {
      final store = MemoryMenuPreferences();
      final window = MethodChannelMenuPreviewWindow(
        preferences: store,
        friends: (_) => Lease(),
      );
      messenger.setMockMethodCallHandler(channel, (_) async => 8);
      final opening = window.openLive(
        contextLabel: 'Trial',
        returnLabel: 'Return',
        settingsLabel: 'Settings',
      );
      await tester.pump();
      await state('visible');
      expect(await opening, true);
      final next = MenuWindowPreferences(0, {
        'version': 1,
        'open': [],
        'panels': [
          {
            'id': 'browser',
            'bounds': [10, 20, 500, 400],
          },
        ],
      }, MenuWindowPreferences.defaults.settings);
      expect(MenuWindowPreferences.parse(next.toMap()), isNotNull);
      Future<void> send(String payload) => messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('preferencesChanged', {'opening': 8, 'payload': payload}),
        ),
        (_) {},
      );
      await send(next.encode());
      await tester.pump(); // Deliver the channel message without advancing the save debounce.
      await state('hidden');
      await send(MenuWindowPreferences.defaults.encode());
      expect(
        store.saved.length,
        1,
      ); // Hiding flushes immediately, not after debounce.
      await tester.pump(const Duration(milliseconds: 400));
      expect(store.saved.length, 1);
      expect(store.value.layout, next.layout);
      window.dispose();
      await tester.pump();
    },
  );

  test(
    'friend commands require a live lease, bounded fields and current opening',
    () async {
      final lease = FriendActionLease();
      messenger.setMockMethodCallHandler(channel, (_) async => 6);
      final window = MethodChannelMenuPreviewWindow(friends: (_) => lease);
      Future<void> event(String method, Map<String, Object?> args) =>
          messenger.handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, args),
            ),
            (_) {},
          );
      final shown = window.openLive(
        contextLabel: 'Trial',
        returnLabel: 'Return',
        settingsLabel: 'Settings',
      );
      await Future<void>.delayed(Duration.zero);
      await state('visible');
      expect(await shown, true);
      final valid = <String, Object?>{
        'opening': 6,
        'action': 'prepare',
        'key': 'f1',
        'value': 'remove',
      };
      await event('friendsAction', valid);
      expect(lease.actions, isEmpty);
      await event('friendsVisible', {'opening': 6, 'visible': true});
      for (final bad in <Map<String, Object?>>[
        {'opening': 5},
        {'action': 'execute'},
        {'key': 'x' * 65},
        {'value': 'x' * 129},
        {'key': 123},
      ]) {
        await event('friendsAction', {...valid, ...bad});
      }
      expect(lease.actions, isEmpty);
      await event('friendsAction', valid);
      expect(lease.actions, ['prepare/f1/remove']);
      await state('hidden');
      await event('friendsAction', valid);
      expect(lease.actions.length, 1);
      window.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'compose bridge whitelists payload and rejects stale or hidden opening',
    () async {
      final lease = ComposeLease();
      messenger.setMockMethodCallHandler(channel, (_) async => 5);
      final window = MethodChannelMenuPreviewWindow(
        friends: (_) => Lease(),
        comms: (_) => lease,
      );
      Future<void> event(String method, Map<String, Object?> args) =>
          messenger.handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(method, args),
            ),
            (_) {},
          );
      final shown = window.openLive(
        contextLabel: 'Trial',
        returnLabel: 'Return',
        settingsLabel: 'Settings',
      );
      await Future<void>.delayed(Duration.zero);
      await state('visible');
      expect(await shown, true);
      await event('commsVisible', {'opening': 5, 'visible': true});
      final valid = <String, Object?>{
        'opening': 5,
        'action': 'send',
        'key': 'c1',
        'text': 'hello',
        'revision': 2,
      };
      for (final bad in <Map<String, Object?>>[
        {'opening': 4},
        {'action': 'delete'},
        {'text': 'x' * 1001},
        {'revision': -1},
        {'revision': 1.5},
        {'key': 'x' * 65},
      ]) {
        await event('commsCompose', {...valid, ...bad});
      }
      expect(lease.calls, isEmpty);
      await event('commsCompose', valid);
      expect(lease.calls, ['send/c1/hello/2']);
      await state('hidden');
      await event('commsCompose', valid);
      expect(lease.calls.length, 1);
      window.dispose();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'real lease is lazy, opening-scoped and stopped when native hides',
    () async {
      final lease = Lease();
      var creations = 0;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'preview' ? 5 : null;
      });
      final window = MethodChannelMenuPreviewWindow(
        friends: (publish) {
          creations++;
          return lease;
        },
      );
      Future<void> panel(int opening, bool visible) =>
          messenger.handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('friendsVisible', {
                'opening': opening,
                'visible': visible,
              }),
            ),
            (_) {},
          );
      final shown = window.openLive(
        contextLabel: 'Trial',
        returnLabel: 'Return',
        settingsLabel: 'Settings',
      );
      await Future<void>.delayed(Duration.zero);
      await state('visible');
      expect(await shown, true);
      expect(creations, 0);
      await panel(4, true);
      expect(creations, 0);
      await panel(5, true);
      expect(creations, 1);
      expect(lease.visibility, [true]);
      await state('hidden');
      expect(lease.visibility.last, false);
      await panel(5, true);
      expect(lease.visibility.last, false);
      window.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(lease.disposed, true);
      expect(calls.last.method, 'detach');
    },
  );

  test(
    'request success alone is not display success; waits for native visible',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return 7;
      });
      final preview = MethodChannelMenuPreviewWindow();
      var completed = false;
      final result = open(preview)..then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, false);
      expect(await open(preview), false);
      expect(calls, ['preview']);
      await state('visible');
      expect(await result, true);
    },
  );

  test('hidden opening reports failure and can retry', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => 1);
    final preview = MethodChannelMenuPreviewWindow();
    final first = open(preview);
    await Future<void>.delayed(Duration.zero);
    await state('hidden');
    expect(await first, false);
    final retry = open(preview);
    await Future<void>.delayed(Duration.zero);
    await state('visible');
    expect(await retry, true);
  });

  test(
    'missing native implementation does not launch external process',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw MissingPluginException(),
      );
      expect(await open(MethodChannelMenuPreviewWindow()), false);
    },
  );

  testWidgets('timeout closes pending native menu and allows retry', (
    tester,
  ) async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return 1;
    });
    final result = open(MethodChannelMenuPreviewWindow());
    await tester.pump();
    await tester.pump(const Duration(seconds: 7));
    expect(await result, false);
    expect(calls, ['preview', 'close']);
  });
}
