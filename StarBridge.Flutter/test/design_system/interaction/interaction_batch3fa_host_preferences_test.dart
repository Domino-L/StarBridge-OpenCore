import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_binding.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_module.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_projection.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences_store.dart';
import 'package:starbridge_flutter/app/preferences/bridge_app_preferences.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_binding.dart';
import 'package:starbridge_flutter/app/social_windows/window_presentation.dart';
import 'package:starbridge_flutter/app/tray/tray_application_binding.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/window/menu_interaction_presentation.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/friends_window/friends_window_binding_test.dart' as friends;
import '../../app/social_windows/social_window_test.dart' as social;

// The optional executable links the original C# dispatcher/store, not a Dart
// replica. No user configuration, credentials, desktop windows or registry.
// Supply both environment variables and enable the existing menu build gate.
final _worker = Platform.environment['STARBRIDGE_INTERACTION_HOST_WORKER'];
final _data = Platform.environment['STARBRIDGE_INTERACTION_HOST_DATA'];
final _skip = _worker == null || _data == null
    ? 'requires isolated original-Host worker and test-data root'
    : false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final style in InteractionStyle.values) {
    final baseline = InteractionStyle.values[(style.index + 1) % 4];

    for (final rejected in [false, true]) {
      testWidgets('$style real Host ${rejected ? 'reject' : 'confirm'} reaches '
          'main root and already-open dialog', (tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = (await tester.runAsync(_Harness.start))!;
        addTearDown(() => tester.runAsync(h.close));
        await tester.runAsync(() async {
          expect(await h.owner.setInteractionStyle(baseline), isTrue);
        });
        final app = AppComposition.forTest(
          windowChrome: InMemoryWindowChrome(),
          preferences: h.owner,
        );
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          StarBridgeApp(composition: app, navigatorKey: nav),
        );
        await tester.pumpAndSettle();
        unawaited(
          nav.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Host wire route')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        unawaited(
          showStarBridgeDialog<void>(
            tester.element(find.text('Host wire route')),
            builder: (_) => const Text('Host wire dialog'),
          ),
        );
        await tester.pumpAndSettle();
        void expectSuite(InteractionStyle value, {bool reduce = false}) {
          for (final label in ['Host wire route', 'Host wire dialog']) {
            final settings = InteractionScope.of(
              tester.element(find.text(label)),
            );
            expect(settings.suite, interactionSuiteFromName(value.name));
            expect(settings.reduceMotion, reduce);
          }
        }

        expectSuite(baseline);
        late Future<bool> saving;
        await tester.runAsync(() async {
          await h.wire.command('configure', {
            'holdNextReply': true,
            'failNextSave': rejected,
          });
          saving = h.owner.setInteractionStyle(style);
          expect((await h.wire.event('held'))['committed'], !rejected);
        });
        await tester.pump();
        await tester.pump();
        expectSuite(style);
        expect(h.owner.projection.value.confirmed!.interactionStyle, baseline);
        await tester.runAsync(() async {
          await h.wire.command('release');
          expect(await saving, !rejected);
        });
        await tester.pump();
        await tester.pump();
        expectSuite(rejected ? baseline : style);
        await tester.runAsync(() async {
          expect(
            await h.owner.setMotionPreference(MotionPreference.reduce),
            isTrue,
          );
        });
        await tester.pump();
        await tester.pump();
        expectSuite(rejected ? baseline : style, reduce: true);
        nav.currentState!.pop();
        await tester.pumpAndSettle();
        nav.currentState!.pop();
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        expect(tester.takeException(), isNull);
      }, skip: _skip != false);
    }

    test('$style real file survives process and Flutter owner reopen', () async {
      final h = await _Harness.start();
      addTearDown(h.close);
      expect(await h.owner.setLocale(const Locale('zh', 'TW')), isTrue);
      expect(await h.owner.setAppearanceMode(AppearanceMode.light), isTrue);
      expect(
        await h.owner.setMotionPreference(MotionPreference.reduce),
        isTrue,
      );
      final behavior = ApplicationBehaviorPreferences.defaults.copyWith(
        startMinimized: true,
        startupChoiceMade: true,
        closeBehaviorChoiceMade: true,
        backgroundHintShown: true,
      );
      expect(await h.owner.setApplicationBehavior(behavior), isTrue);
      await h.wire.command('configure', {'holdNextReply': true});
      final saving = h.owner.setInteractionStyle(style);
      expect(
        h.owner.projection.value.operation,
        AppPreferencesOperation.saving,
      );
      expect(
        h.owner.projection.value.confirmed!.interactionStyle,
        InteractionStyle.standard,
      );
      final held = await h.wire.event('held');
      expect(held['committed'], isTrue);
      expect((held['snapshot'] as Map)['interactionStyle'], style.name);
      // Persistence is real even while the original reply is held in transport.
      expect(h.owner.projection.value.revision, 4);
      expect(await h.owner.setInteractionStyle(baseline), isFalse);
      await h.wire.command('release');
      expect(await saving, isTrue);
      expect(h.owner.projection.value.revision, 5);
      final root = h.wire.root;
      await h.close();
      final reopened = await _Harness.start(root: root);
      addTearDown(reopened.close);
      final p = reopened.owner.projection.value;
      expect(p.source, AppPreferencesSource.stored);
      expect(p.revision, 5);
      expect(p.confirmed!.interactionStyle, style);
      expect(p.effective.interactionStyle, style);
      expect(p.effective.locale, const Locale('zh', 'TW'));
      expect(p.effective.appearanceMode, AppearanceMode.light);
      expect(p.effective.motionPreference, MotionPreference.reduce);
      expect(p.confirmed!.applicationBehavior.startMinimized, isTrue);
      expect(p.confirmed!.applicationBehavior.launchAtStartup, isFalse);
      expect(p.confirmed!.applicationBehavior.startupChoiceMade, isTrue);
      expect(p.confirmed!.applicationBehavior.closeBehaviorChoiceMade, isTrue);
      expect(p.confirmed!.applicationBehavior.backgroundHintShown, isTrue);
      expect(reopened.wire.requests.map((e) => e.name), [
        'applicationPreferences.get',
      ]);
    }, skip: _skip);

    for (final rejected in [false, true]) {
      test('$style pending / ${rejected ? 'rollback' : 'confirm'} publishes to '
          'real friends messages inbox tray and composed menu bindings', () async {
        final h = await _Harness.start();
        addTearDown(h.close);
        expect(await h.owner.setInteractionStyle(baseline), isTrue);
        final windows = await _Windows.open(h.owner);
        addTearDown(windows.close);
        await windows.expectStyle(baseline);
        final scopes = windows.scopes;
        await h.wire.command('configure', {
          'holdNextReply': true,
          'failNextSave': rejected,
        });
        final saving = h.owner.setInteractionStyle(style);
        expect(h.owner.projection.value.confirmed!.interactionStyle, baseline);
        await windows.expectStyle(style);
        expect(windows.scopes, scopes);
        final held = await h.wire.event('held');
        expect(held['committed'], !rejected);
        expect(
          (held['snapshot'] as Map)['interactionStyle'],
          rejected ? baseline.name : style.name,
        );
        await h.wire.command('release');
        expect(await saving, !rejected);
        expect(
          h.owner.projection.value.failure,
          rejected ? AppPreferencesFailure.saveFailed : null,
        );
        expect(h.owner.projection.value.revision, rejected ? 1 : 2);
        await windows.expectStyle(rejected ? baseline : style);
        expect(windows.scopes, scopes);
        expect(
          await h.owner.setMotionPreference(MotionPreference.reduce),
          isTrue,
        );
        await windows.expectReduced();
        expect(windows.scopes, scopes);
        windows.close();
        await _until(
          () => windows.calls.values.every(
            (calls) => calls.any((call) => call.method == 'detach'),
          ),
        );
        final afterDispose = windows.publicationCount;
        expect(await h.owner.setInteractionStyle(baseline), isTrue);
        // Await a real roundtrip rather than pumping an arbitrary frame count.
        await h.wire.command('status');
        expect(windows.publicationCount, afterDispose);
      }, skip: _skip);
    }

    test(
      '$style lost reply is uncertain; reconnect reads actual committed file',
      () async {
        final h = await _Harness.start();
        addTearDown(h.close);
        expect(await h.owner.setInteractionStyle(baseline), isTrue);
        await h.wire.command('configure', {'dropNextReply': true});
        final saving = h.owner.setInteractionStyle(style);
        final lost = await h.wire.event('dropped');
        expect(lost['committed'], isTrue);
        expect((lost['snapshot'] as Map)['interactionStyle'], style.name);
        await h.wire.disconnect();
        expect(await saving, isFalse);
        expect(
          h.owner.projection.value.failure,
          AppPreferencesFailure.outcomeUncertain,
        );
        expect(h.owner.projection.value.confirmed!.interactionStyle, baseline);
        expect(h.owner.projection.value.revision, 1);
        await h.session.close();
        final replacement = await _WorkerWire.start(root: h.wire.root);
        final session = BridgeClientSession(
          connection: replacement,
          sessionGeneration: 7,
        );
        addTearDown(session.close);
        await h.owner.attachStore(BridgeAppPreferencesStore(session));
        expect(h.owner.projection.value.failure, isNull);
        expect(h.owner.projection.value.revision, 2);
        expect(h.owner.projection.value.confirmed!.interactionStyle, style);
        expect(replacement.requests.map((e) => e.name), [
          'applicationPreferences.get',
        ], reason: 'No blind update replay');
      },
      skip: _skip != false,
    );

    test(
      '$style old held success cannot overwrite replacement owner binding',
      () async {
        final h = await _Harness.start();
        addTearDown(h.close);
        await h.wire.command('configure', {'holdNextReply': true});
        final saving = h.owner.setInteractionStyle(style);
        await h.wire.event('held');
        final replacement = await _Harness.start();
        addTearDown(replacement.close);
        expect(await replacement.owner.setInteractionStyle(baseline), isTrue);
        await h.owner.attachStore(
          BridgeAppPreferencesStore(replacement.session),
        );
        await h.wire.command('release');
        expect(await saving, isFalse);
        expect(h.owner.projection.value.confirmed!.interactionStyle, baseline);
        expect(h.owner.projection.value.revision, 1);
        expect(h.owner.projection.value.failure, isNull);
      },
      skip: _skip,
    );

    test(
      '$style detach rejects late result; reattach reads committed snapshot',
      () async {
        final h = await _Harness.start();
        addTearDown(h.close);
        await h.wire.command('configure', {'holdNextReply': true});
        final saving = h.owner.setInteractionStyle(style);
        await h.wire.event('held');
        h.owner.detachStore();
        await h.wire.command('release');
        expect(await saving, isFalse);
        expect(h.owner.projection.value.phase, AppPreferencesPhase.unavailable);
        expect(h.owner.projection.value.revision, 0);
        expect(
          h.owner.projection.value.confirmed!.interactionStyle,
          InteractionStyle.standard,
        );
        await h.owner.attachStore(BridgeAppPreferencesStore(h.session));
        expect(h.owner.projection.value.revision, 1);
        expect(h.owner.projection.value.confirmed!.interactionStyle, style);
      },
      skip: _skip,
    );

    test(
      '$style stale revision rereads actual newer Host value without replay',
      () async {
        final h = await _Harness.start();
        addTearDown(h.close);
        // A second real Bridge store writes while the original owner is stale.
        final second = BridgeAppPreferencesStore(h.session);
        expect((await second.read()).revision, 0);
        expect(
          (await second.update(
            AppPreferencesPatch.interaction(baseline),
            expectedRevision: 0,
          )).revision,
          1,
        );
        final count = h.wire.requests.length;
        expect(await h.owner.setInteractionStyle(style), isFalse);
        expect(
          h.owner.projection.value.failure,
          AppPreferencesFailure.revisionConflict,
        );
        expect(h.owner.projection.value.confirmed!.interactionStyle, baseline);
        expect(h.owner.projection.value.revision, 1);
        expect(h.wire.requests.skip(count).map((e) => e.name), [
          'applicationPreferences.update',
          'applicationPreferences.get',
        ]);
        expect(
          (await h.wire.command('status'))['snapshot'],
          containsPair('revision', 1),
        );
      },
      skip: _skip,
    );
  }
}

Future<void> _until(bool Function() predicate) async {
  final end = DateTime.now().add(const Duration(seconds: 8));
  while (!predicate()) {
    if (DateTime.now().isAfter(end)) fail('Timed out awaiting fixture event');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class _Harness {
  _Harness(this.wire, this.session, this.owner);
  final _WorkerWire wire;
  final BridgeClientSession session;
  final AppPreferencesModule owner;
  bool _closed = false;
  static Future<_Harness> start({String? root}) async {
    final wire = await _WorkerWire.start(root: root);
    final session = BridgeClientSession(connection: wire, sessionGeneration: 7);
    final owner = AppPreferencesModule();
    final h = _Harness(wire, session, owner);
    try {
      await owner.attachStore(BridgeAppPreferencesStore(session));
      expect(owner.projection.value.canEdit, isTrue);
      return h;
    } catch (_) {
      await h.close();
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    owner.dispose();
    await session.close();
  }
}

class _WorkerWire implements BridgeConnection {
  _WorkerWire(this.process, this.root) {
    _stdout = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            final value = (jsonDecode(line) as Map).cast<String, Object?>();
            if (value.containsKey('worker')) {
              controls.add(value);
            } else if (!_incoming.isClosed) {
              _incoming.add(BridgeEnvelope.fromJson(value));
            }
          },
          onDone: () {
            if (!_incoming.isClosed) unawaited(_incoming.close());
          },
        );
    _stderr = process.stderr.transform(utf8.decoder).listen(errors.add);
  }
  final Process process;
  final String root;
  final _incoming = StreamController<BridgeEnvelope>.broadcast();
  final controls = <Map<String, Object?>>[];
  final requests = <BridgeEnvelope>[];
  final errors = <String>[];
  late final StreamSubscription<String> _stdout, _stderr;
  int _sequence = 0;
  bool _closed = false;
  static Future<_WorkerWire> start({String? root}) async {
    final parent = await Directory(_data!).create(recursive: true);
    root ??= (await parent.createTemp('flutter-wire-')).path;
    final process = await Process.start(_worker!, [
      '--root',
      root,
      '--generation',
      '7',
    ]);
    return _WorkerWire(process, root);
  }

  @override
  Stream<BridgeEnvelope> get incoming => _incoming.stream;
  @override
  Future<void> send(BridgeEnvelope envelope) async {
    requests.add(envelope);
    process.stdin.writeln(jsonEncode(envelope.toJson()));
    await process.stdin.flush();
  }

  Future<Map<String, Object?>> command(
    String command, [
    Map<String, Object?> values = const {},
  ]) async {
    final id = 'control-${++_sequence}';
    process.stdin.writeln(jsonEncode({'worker': command, 'id': id, ...values}));
    await process.stdin.flush();
    await _until(() => controls.any((e) => e['id'] == id));
    final result = controls.firstWhere((e) => e['id'] == id);
    expect(result['worker'], isNot('error'), reason: '$result');
    return result;
  }

  Future<Map<String, Object?>> event(String kind) async {
    await _until(() => controls.any((e) => e['worker'] == kind));
    return controls.firstWhere((e) => e['worker'] == kind);
  }

  Future<void> disconnect() async {
    if (!_incoming.isClosed) await _incoming.close();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await process.stdin.close();
    final code = await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    await _stdout.cancel();
    await _stderr.cancel();
    await disconnect();
    expect(code, 0, reason: errors.join());
  }
}

// Only OS window transport and unrelated business ports are fixtures; all five
// preference consumers and the menu composition below are original production.
class _Windows {
  _Windows(this.owner);
  final AppPreferencesModule owner;
  final calls = <String, List<MethodCall>>{};
  final menu = <MenuInteractionPresentation>[];
  final _inbox = NotificationInboxController(null);
  final _chrome = ValueNotifier(InMemoryShellChrome.connectedProjection);
  late final AppComposition _app;
  late final FriendsWindowBinding _friends;
  final _social = <SocialWindowBinding>[];
  late final TrayApplicationBinding _tray;
  late final MenuInteractionFeed _feed;
  bool detached = false;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  static Future<_Windows> open(AppPreferencesModule owner) async {
    final w = _Windows(owner);
    for (final kind in ['friends', 'messages', 'notifications', 'tray']) {
      w.calls[kind] = [];
      w.messenger.setMockMethodCallHandler(
        MethodChannel('starbridge/$kind-primary'),
        (call) async {
          w.calls[kind]!.add(call);
          return call.method == 'show' ? true : null;
        },
      );
    }
    w._app = AppComposition.forShellReview(
      preferences: owner,
      windowChrome: InMemoryWindowChrome(),
    );
    // This intentionally requires the same build gate as the real menu client.
    w._feed =
        (w._app.overlaySettings.menuPreview! as MethodChannelMenuPreviewWindow)
            .interaction!;
    w._feed.start(
      isCurrent: () => !w.detached,
      publish: (value) => w.menu.add(MenuInteractionPresentation.parse(value)!),
    );
    w._tray = TrayApplicationBinding(
      preferences: owner.projection,
      chrome: w._chrome,
      overlay: w._app.overlaySettings,
      openOverlaySettings: () async {},
    );
    w._friends = FriendsWindowBinding(
      preferences: owner,
      create: (publish) => MenuFriendsSession(friends.Port(), publish),
      openChat: (_, _) async {},
      openMessages: (_) async {},
      openProfile: (_) async {},
    );
    expect(await w._friends.open(), isTrue);
    for (final kind in ['messages', 'notifications']) {
      final binding = SocialWindowBinding(
        kind: kind,
        preferences: owner,
        messages: social.Port(),
        inbox: w._inbox,
        navigate: (_) async {},
      );
      w._social.add(binding);
      expect(await binding.open(), isTrue);
    }
    return w;
  }

  Map get _traySnapshot =>
      calls['tray']!.lastWhere((c) => c.method == 'configure').arguments as Map;
  Map _last(String kind) =>
      calls[kind]!
              .lastWhere((c) => c.method == 'show' || c.method == 'snapshot')
              .arguments
          as Map;
  List<Object?> get scopes => [
    for (final kind in ['friends', 'messages', 'notifications'])
      (jsonDecode(_last(kind)['view'] as String) as Map)['scope'],
    _traySnapshot['scope'],
  ];
  int get publicationCount =>
      calls.values.fold(0, (n, v) => n + v.length) + menu.length;
  Future<void> expectStyle(InteractionStyle style) async {
    await _until(
      () =>
          menu.isNotEmpty &&
          menu.last.style.name == style.name &&
          calls['tray']!.any((c) => c.method == 'configure') &&
          _traySnapshot['interactionStyle'] == style.name &&
          ['friends', 'messages', 'notifications'].every(
            (kind) =>
                ((_last(kind)['presentation']) as Map)['interactionStyle'] ==
                style.name,
          ),
    );
    for (final kind in ['friends', 'messages', 'notifications']) {
      final presentation = _last(kind)['presentation'] as Map;
      expect(
        WindowPresentation.decode(presentation).interactionSuite,
        interactionSuiteFromName(style.name),
      );
    }
  }

  Future<void> expectReduced() async {
    await _until(
      () =>
          menu.last.reduceMotion &&
          _traySnapshot['reduceMotion'] == true &&
          ['friends', 'messages', 'notifications'].every(
            (kind) =>
                (_last(kind)['presentation'] as Map)['reduceMotion'] == true,
          ),
    );
  }

  void close() {
    if (detached) return;
    detached = true;
    _feed.stop();
    _friends.dispose();
    for (final binding in _social) {
      binding.dispose();
    }
    _tray.dispose();
    _chrome.dispose();
    _inbox.dispose();
    // Keep recorders through one real Host roundtrip to detect stray publishes.
    addTearDown(() {
      _app.dispose();
      for (final kind in calls.keys) {
        messenger.setMockMethodCallHandler(
          MethodChannel('starbridge/$kind-primary'),
          null,
        );
      }
    });
  }
}

/// Test-only seam for subsequent real-input integration tests. This delegates
/// to the original isolated worker/harness above; it does not recreate storage,
/// replies, preference ownership, or the JSON-lines transport algorithm.
class InteractionHostPreferencesFixture {
  InteractionHostPreferencesFixture._(this._harness);
  final _Harness _harness;

  static bool get available => _skip == false;

  static Future<InteractionHostPreferencesFixture> start({String? root}) async =>
      InteractionHostPreferencesFixture._(await _Harness.start(root: root));

  AppPreferencesModule get owner => _harness.owner;
  String get root => _harness.wire.root;

  // Observation of actual requests, not a simulated write acknowledgement.
  int get updateRequests => _harness.wire.requests
      .where((request) => request.name == 'applicationPreferences.update')
      .length;

  Future<void> configureHeldSave({required bool rejected}) async {
    await _harness.wire.command('configure', {
      'holdNextReply': true,
      'failNextSave': rejected,
    });
  }

  Future<Map<String, Object?>> heldEvent() => _harness.wire.event('held');

  Future<void> release() async {
    await _harness.wire.command('release');
  }

  Future<void> close() => _harness.close();
}
