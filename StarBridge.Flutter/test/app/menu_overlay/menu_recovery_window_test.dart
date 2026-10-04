import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/platform/window/menu_recovery.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';

import 'menu_preview_window_test.dart' show MemoryMenuPreferences, Lease;
import 'menu_startup_lifecycle_test.dart' show StartupFixture;

class Recovery implements MenuRecoveryPort {
  bool interrupted = true, fail = false;
  int finished = 0;
  @override
  Future<MenuRecoverySession> begin() async {
    if (fail) throw StateError('storage unavailable');
    return MenuRecoverySession('a' * 32, interrupted);
  }

  @override
  Future<void> finish(String token) async {
    finished++;
  }
}

class Preferences extends MemoryMenuPreferences {
  bool fail = false;
  Completer<void>? blocked;
  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences next) async {
    await blocked?.future;
    if (fail) throw StateError('conflict');
    return super.save(next);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('starbridge/menu-primary');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  int request = 0;
  Future<Object?> event(String method, Object? args) async {
    final reply = Completer<Object?>();
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (data) {
        try {
          reply.complete(
            data == null
                ? null
                : const StandardMethodCodec().decodeEnvelope(data),
          );
        } on Object catch (error) {
          reply.completeError(error);
        }
      },
    );
    return reply.future;
  }

  Future<void> reveal(
    WidgetTester tester,
    MethodChannelMenuPreviewWindow window,
  ) async {
    final result = window.openLive(
      contextLabel: 'Menu',
      returnLabel: 'Return',
      settingsLabel: 'Settings',
    );
    await tester.pump();
    await event('state', {'request': request, 'state': 'visible'});
    expect(await result, true);
  }

  Preferences preferences() => Preferences()
    ..value = const MenuWindowPreferences(
      3,
      {
        'version': 1,
        'panels': [],
        'open': ['friends', 'browser'],
      },
      {
        'showClock': true,
        'showContext': true,
        'dimming': .5,
        'restoreDesktop': true,
      },
    );
  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'preview') {
        request = (call.arguments as Map)['request'] as int;
      }
      return call.method == 'preview' ? 7 : null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  for (final safe in [true, false]) {
    testWidgets(
      'startup mode protects saved layout and asks for no recovery or tools; verified=$safe',
      (tester) async {
        final startup = StartupFixture(
          payload: safe
              ? {'schemaVersion': 1, 'safe': true}
              : {'schemaVersion': 1, 'safe': 'invalid'},
        );
        addTearDown(startup.close);
        final lifetime = MenuWindowLifetime();
        await lifetime.prepareStartup(startup.session);
        final store = preferences();
        store.value = store.value.withSettingsPatch({
          'crashRecovery': 'startClean',
        });
        final original = store.value;
        var leases = 0;
        final recovery = Recovery();
        final window = MethodChannelMenuPreviewWindow(
          lifetime: lifetime,
          preferences: store,
          recovery: recovery,
          friends: (_) {
            leases++;
            return Lease();
          },
        );
        await reveal(tester, window);
        final args =
            calls.lastWhere((c) => c.method == 'preview').arguments as Map;
        expect(args['startupMode'], safe ? 'safe' : 'unverified');
        expect(args['recoveryPending'], false);
        expect(
          jsonDecode(args['preferences'] as String)['layout']['open'],
          isEmpty,
        );
        expect(store.saved, isEmpty);
        expect(leases, 0);
        await event('preferencesChanged', {
          'opening': 7,
          'payload': MenuWindowPreferences(original.revision, const {
            'version': 1,
            'panels': [],
            'open': [],
          }, original.settings).encode(),
        });
        await lifetime.completeExit();
        expect(store.saved, isEmpty);
        expect(store.value.layout, original.layout);
        await event('friendsVisible', {'opening': 7, 'visible': true});
        expect(leases, 1); // A user may explicitly open an authorized tool.
        await event('preferencesChanged', {
          'opening': 7,
          'payload': MenuWindowPreferences(
            original.revision,
            const {'version': 1, 'panels': [], 'open': []},
            {...original.settings, 'safeModeNextLaunch': true},
          ).encode(),
        });
        await lifetime.completeExit();
        expect(store.value.settings['safeModeNextLaunch'], true);
        expect(store.value.layout, original.layout);
        expect(recovery.finished, 0);
        window.dispose();
        await tester.pump();
      },
    );
  }
  for (final mode in ['restore', 'startClean']) {
    testWidgets('primary consumes explicit $mode without recovery dialog', (
      tester,
    ) async {
      final store = preferences();
      store.value = store.value.withSettingsPatch({'crashRecovery': mode});
      var leases = 0;
      final window = MethodChannelMenuPreviewWindow(
        lifetime: MenuWindowLifetime(),
        preferences: store,
        recovery: Recovery(),
        friends: (_) {
          leases++;
          return Lease();
        },
      );
      await reveal(tester, window);
      final args =
          calls.lastWhere((c) => c.method == 'preview').arguments as Map;
      expect(args['recoveryPending'], false);
      expect(
        jsonDecode(args['preferences'] as String)['layout']['open'],
        mode == 'restore' ? ['friends', 'browser'] : isEmpty,
      );
      expect(store.saved, hasLength(mode == 'restore' ? 0 : 1));
      expect(leases, 0); // A prepared layout does not itself authorize a read.
      await event('friendsVisible', {'opening': 7, 'visible': true});
      expect(leases, 1);
      window.dispose();
      await tester.pump();
    });
  }
  for (final session in [false, true]) {
    for (final restart in [false, true]) {
      testWidgets('independent restoration session=$session restart=$restart', (
        tester,
      ) async {
        final store = preferences();
        store.value = store.value.withSettingsPatch({
          'restoreDesktop': session,
          'restoreAfterRestart': restart,
        });
        // When both are disabled, no persisted opened-tool list is accepted.
        final expected = session || restart
            ? ['friends', 'browser']
            : <String>[];
        final recovery = Recovery()..interrupted = false;
        final lifetime = MenuWindowLifetime();
        MethodChannelMenuPreviewWindow create() =>
            MethodChannelMenuPreviewWindow(
              lifetime: lifetime,
              preferences: store,
              recovery: recovery,
              friends: (_) => Lease(),
            );
        var window = create();
        List opened() =>
            jsonDecode(
                  (calls.lastWhere((c) => c.method == 'preview').arguments
                          as Map)['preferences']
                      as String,
                )['layout']['open']
                as List;
        await reveal(tester, window);
        expect(opened(), restart ? expected : isEmpty);
        // A replaced composition is not a process restart; ownership is shared.
        window.dispose();
        window = create();
        await reveal(tester, window);
        expect(opened(), session ? expected : isEmpty);
        window.dispose();
        await tester.pump();
        window = MethodChannelMenuPreviewWindow(
          lifetime: MenuWindowLifetime(),
          preferences: store,
          recovery: recovery,
          friends: (_) => Lease(),
        );
        await reveal(tester, window);
        expect(opened(), restart ? expected : isEmpty);
        window.dispose();
        await tester.pump();
      });
    }
  }
  testWidgets(
    'restart-only pending consent re-asks after hide without erasing layout',
    (tester) async {
      final store = preferences();
      store.value = store.value.withSettingsPatch({
        'restoreDesktop': false,
        'restoreAfterRestart': true,
      });
      final window = MethodChannelMenuPreviewWindow(
        lifetime: MenuWindowLifetime(),
        preferences: store,
        recovery: Recovery(),
        friends: (_) => Lease(),
      );
      await reveal(tester, window);
      await event('state', {'request': request, 'state': 'hidden'});
      await reveal(tester, window);
      expect(
        (calls.lastWhere((c) => c.method == 'preview').arguments
            as Map)['recoveryPending'],
        true,
      );
      expect(store.saved, isEmpty);
      expect(store.value.layout['open'], ['friends', 'browser']);
      await event('recoveryAction', {'opening': 7, 'action': 'restore'});
      await event('state', {'request': request, 'state': 'hidden'});
      await reveal(tester, window);
      final args =
          calls.lastWhere((c) => c.method == 'preview').arguments as Map;
      expect(args['recoveryPending'], false);
      expect(
        jsonDecode(args['preferences'] as String)['layout']['open'],
        isEmpty,
      );
      window.dispose();
      await tester.pump();
    },
  );
  for (final action in ['restore', 'startClean']) {
    testWidgets(
      'interruption gates tools and saves only after $action consent',
      (tester) async {
        final store = preferences(),
            recovery = Recovery(),
            lifetime = MenuWindowLifetime();
        var leases = 0;
        final window = MethodChannelMenuPreviewWindow(
          lifetime: lifetime,
          preferences: store,
          recovery: recovery,
          friends: (_) {
            leases++;
            return Lease();
          },
        );
        await reveal(tester, window);
        final args =
            calls.firstWhere((c) => c.method == 'preview').arguments as Map;
        expect(args['recoveryPending'], true);
        expect(
          (jsonDecode(args['preferences'] as String)['layout'] as Map)['open'],
          isEmpty,
        );
        await event('friendsVisible', {'opening': 7, 'visible': true});
        await event('preferencesChanged', {
          'opening': 7,
          'payload': MenuWindowPreferences.defaults.encode(),
        });
        expect(leases, 0);
        expect(store.saved, isEmpty);
        final result = MenuWindowPreferences.parse(
          jsonDecode(
            await event('recoveryAction', {'opening': 7, 'action': action})
                as String,
          ),
        )!;
        expect(
          result.layout['open'],
          action == 'restore' ? ['friends', 'browser'] : isEmpty,
        );
        expect(store.saved.length, action == 'restore' ? 0 : 1);
        final repeated = await event('recoveryAction', {
          'opening': 7,
          'action': action,
        });
        expect(repeated, result.encode());
        expect(store.saved.length, action == 'restore' ? 0 : 1);
        await event('friendsVisible', {'opening': 7, 'visible': true});
        expect(leases, 1);
        await event('state', {'request': request, 'state': 'hidden'});
        expect(recovery.finished, 0);
        await reveal(tester, window);
        expect(
          (calls.lastWhere((c) => c.method == 'preview').arguments
              as Map)['recoveryPending'],
          false,
        );
        await lifetime.completeExit();
        expect(recovery.finished, 1);
        window.dispose();
        await tester.pump();
        expect(recovery.finished, 1);
      },
    );
  }
  testWidgets(
    'failed clean choice preserves layout and can retry; hide re-asks',
    (tester) async {
      final store = preferences()..fail = true;
      final recovery = Recovery(), lifetime = MenuWindowLifetime();
      final window = MethodChannelMenuPreviewWindow(
        lifetime: lifetime,
        preferences: store,
        recovery: recovery,
        friends: (_) => Lease(),
      );
      await reveal(tester, window);
      await expectLater(
        event('recoveryAction', {'opening': 7, 'action': 'startClean'}),
        throwsA(isA<PlatformException>()),
      );
      expect(store.value.layout['open'], ['friends', 'browser']);
      await event('state', {'request': request, 'state': 'hidden'});
      await reveal(tester, window);
      expect(
        (calls.lastWhere((c) => c.method == 'preview').arguments
            as Map)['recoveryPending'],
        true,
      );
      store.fail = false;
      await event('recoveryAction', {'opening': 7, 'action': 'startClean'});
      expect(store.value.layout['open'], isEmpty);
      window.dispose();
      await tester.pump();
      expect(recovery.finished, 0);
    },
  );
  testWidgets(
    'unknown marker blocks automatic restore; normal start does not ask',
    (tester) async {
      for (final failed in [true, false]) {
        final recovery = Recovery()
          ..fail = failed
          ..interrupted = false;
        final window = MethodChannelMenuPreviewWindow(
          lifetime: MenuWindowLifetime(),
          preferences: preferences(),
          recovery: recovery,
          friends: (_) => Lease(),
        );
        await reveal(tester, window);
        expect(
          (calls.lastWhere((c) => c.method == 'preview').arguments
              as Map)['recoveryPending'],
          failed,
        );
        window.dispose();
        await tester.pump();
      }
    },
  );
  testWidgets('late recovery completion after hide cannot authorize tools', (
    tester,
  ) async {
    final store = preferences()..blocked = Completer<void>();
    final window = MethodChannelMenuPreviewWindow(
      lifetime: MenuWindowLifetime(),
      preferences: store,
      recovery: Recovery(),
      friends: (_) => Lease(),
    );
    await reveal(tester, window);
    final response = event('recoveryAction', {
      'opening': 7,
      'action': 'startClean',
    });
    final rejected = expectLater(response, throwsA(isA<PlatformException>()));
    await tester.pump();
    await event('state', {'request': request, 'state': 'hidden'});
    store.blocked!.complete();
    await rejected;
    window.dispose();
    await tester.pump();
  });

  testWidgets(
    'normal exit flushes pending layout before marking clean; failure leaves interrupted',
    (tester) async {
      for (final fail in [false, true]) {
        final store = preferences()..fail = fail;
        final recovery = Recovery()..interrupted = false;
        final lifetime = MenuWindowLifetime();
        final window = MethodChannelMenuPreviewWindow(
          lifetime: lifetime,
          preferences: store,
          recovery: recovery,
          friends: (_) => Lease(),
        );
        await reveal(tester, window);
        final layout = {
          ...store.value.layout,
          'panels': [
            {
              'id': 'browser',
              'bounds': [10, 20, 500, 400],
            },
          ],
        };
        await event('preferencesChanged', {
          'opening': 7,
          'payload': MenuWindowPreferences(
            store.value.revision,
            layout,
            store.value.settings,
          ).encode(),
        });
        await lifetime.completeExit();
        expect(recovery.finished, fail ? 0 : 1);
        if (!fail) expect(store.value.layout['panels'], layout['panels']);
        window.dispose();
        await tester.pump();
      }
    },
  );
}
