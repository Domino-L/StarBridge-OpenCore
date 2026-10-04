import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/routing/open_destination_intent.dart';
import 'package:starbridge_flutter/app/shell/starbridge_shell.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_flutter/features/settings/settings_page.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/host/native_host_connector.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/app/runtime/startup_prompt_queue.dart';

void main() {
  for (final confirm in [false, true]) {
    testWidgets(
      'legacy confirmation $confirm preserves banner until verified readback',
      (tester) async {
        final host = _MismatchHost()
          ..writable = true
          ..prepareState = 'ready';
        final composition = await _mount(tester, host);
        await _finishReads(tester);
        await tester.tap(find.byKey(const ValueKey('handle-mismatch-recheck')));
        await _finishReads(tester);
        expect(composition.handleMismatch.canConfirm, isTrue);
        expect(
          host.requests.where(
            (r) => r.name == 'gameIdentity.confirmHandleChange',
          ),
          isEmpty,
        );
        expect(find.textContaining('不会修改 RSI 账号'), findsOneWidget);
        await tester.tap(
          find.byKey(
            ValueKey(
              confirm ? 'handle-mismatch-confirm' : 'handle-mismatch-later',
            ),
          ),
        );
        await _finishReads(tester);
        if (confirm) {
          final write = host.requests.singleWhere(
            (r) => r.name == 'gameIdentity.confirmHandleChange',
          );
          expect(write.payload, {
            'schemaVersion': 1,
            'confirmationId': 'a' * 32,
          });
          expect(composition.handleMismatch.notice, isNull);
          expect(
            find.byKey(const ValueKey('handle-mismatch-dialog')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('handle-mismatch-banner')),
            findsNothing,
          );
        } else {
          expect(
            host.requests.where(
              (r) => r.name == 'gameIdentity.cancelHandleChange',
            ),
            hasLength(1),
          );
          expect(
            host.requests.where(
              (r) => r.name == 'gameIdentity.confirmHandleChange',
            ),
            isEmpty,
          );
          expect(composition.handleMismatch.notice, isNotNull);
          expect(composition.handleMismatch.canConfirm, isFalse);
          expect(
            find.byKey(const ValueKey('handle-mismatch-banner')),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final submitted in [true, false]) {
    testWidgets(
      'background mismatch submits once; foreground result $submitted',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        final host = _MismatchHost()..submitted = submitted;
        await _mount(tester, host);
        await _finishReads(tester);
        expect(
          find.byKey(const ValueKey('handle-mismatch-banner')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('handle-mismatch-dialog')),
          findsNothing,
        );
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(seconds: 2));
        }
        final sent = host.requests
            .where((r) => r.name == 'gameIdentity.notifyMismatch')
            .toList();
        expect(sent, hasLength(1));
        expect(sent.single.payload, {'schemaVersion': 1});
        expect(
          sent.single.accountContext?.toJson(),
          _MismatchHost._owner.toJson(),
        );
        expect(sent.single.sessionGeneration, 7);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await _finishReads(tester);
        expect(
          find.byKey(const ValueKey('handle-mismatch-dialog')),
          submitted ? findsNothing : findsOneWidget,
        );
        if (!submitted) {
          await tester.tap(find.byKey(const ValueKey('handle-mismatch-later')));
          await _finishReads(tester);
        }
        // A valid Windows click must remain actionable even after auto dedupe.
        final before = host.requests
            .where((r) => r.name.startsWith('partyRooms.'))
            .length;
        await host.activate();
        await _finishReads(tester);
        expect(
          find.byKey(const ValueKey('handle-mismatch-dialog')),
          findsOneWidget,
        );
        expect(
          host.requests.where((r) => r.name.startsWith('partyRooms.')).length,
          before,
        );
        await tester.tap(find.byKey(const ValueKey('handle-mismatch-account')));
        await _finishReads(tester);
        expect(find.byType(SettingsPage), findsOneWidget);
        expect(
          find.byKey(const ValueKey('handle-mismatch-banner')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'persisted mismatch without game observation has banner, no unsolicited popup',
    (tester) async {
      final host = _MismatchHost()..detected = null;
      final composition = await _mount(tester, host);
      await _finishReads(tester);
      expect(composition.handleMismatch.notice?.detectedHandle, isNull);
      expect(
        find.byKey(const ValueKey('handle-mismatch-banner')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('handle-mismatch-action')));
      await _finishReads(tester);
      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsOneWidget,
      );
      host.prepareState = 'observationRequired';
      await tester.tap(find.byKey(const ValueKey('handle-mismatch-recheck')));
      await _finishReads(tester);
      expect(composition.handleMismatch.failed, isFalse);
      expect(find.textContaining('已有身份记录时，无需重新启动游戏'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('handle-mismatch-banner')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'read-only unknown check cannot enable a rename; stale account dismisses dialog',
    (tester) async {
      final host = _MismatchHost();
      final composition = await _mount(tester, host);
      await _finishReads(tester);
      await tester.tap(find.byKey(const ValueKey('handle-mismatch-recheck')));
      await _finishReads(tester);
      expect(composition.handleMismatch.failed, isFalse);
      expect(composition.handleMismatch.busy, isFalse);
      final request = host.requests.singleWhere(
        (r) => r.name == 'gameIdentity.prepareHandleChange',
      );
      expect(request.payload, {'schemaVersion': 1});
      expect(request.accountContext?.toJson(), _MismatchHost._owner.toJson());
      expect(
        find.byKey(const ValueKey('handle-mismatch-confirm')),
        findsNothing,
      );
      expect(find.textContaining('请先核验账号'), findsOneWidget);
      host.prepareState = 'ready';
      await tester.tap(find.byKey(const ValueKey('handle-mismatch-recheck')));
      await _finishReads(tester);
      expect(composition.handleMismatch.failed, isTrue);
      expect(
        find.byKey(const ValueKey('handle-mismatch-banner')),
        findsOneWidget,
      );
      await host.changeOwner();
      await _finishReads(tester);
      expect(composition.handleMismatch.notice, isNull);
      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('handle-mismatch-banner')),
        findsNothing,
      );
      expect(
        host.requests.where(
          (r) =>
              r.name.contains('confirmHandle') ||
              r.name.contains('rename') ||
              r.name == 'account.logout',
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'automatic identity prompt honors existing startup queue and readiness',
    (tester) async {
      final prompts = StartupPromptQueue();
      final navigator = GlobalKey<NavigatorState>();
      var ready = false;
      await _mount(
        tester,
        _MismatchHost(),
        queue: prompts,
        navigator: navigator,
        ready: () => ready,
      );
      addTearDown(prompts.dispose);
      await _finishReads(tester);
      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsNothing,
      );
      final manual = showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Existing manual route')),
      );
      ready = true;
      prompts.wake();
      await _finishReads(tester);
      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsNothing,
      );
      navigator.currentState!.pop();
      await manual;
      await tester.pump(const Duration(milliseconds: 400));
      await _finishReads(tester);
      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'temporary reads and a match do not re-arm the same difference in this account session',
    (tester) async {
      final host = _MismatchHost();
      final composition = await _mount(tester, host);
      await _finishReads(tester);
      await tester.tap(find.byKey(const ValueKey('handle-mismatch-later')));
      await _finishReads(tester);
      final original = composition.handleMismatch.notice!.key;
      host.accountState = 'legacyUnavailable';
      await composition.account.refresh();
      await _finishReads(tester);
      expect(composition.handleMismatch.notice!.key, original);
      expect(
        find.byKey(const ValueKey('handle-mismatch-banner')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsNothing,
      );
      host.accountState = 'legacySignedIn';
      host.detected = null;
      await composition.account.refresh();
      await composition.gameLog!.run();
      await _finishReads(tester);
      expect(composition.handleMismatch.notice!.key, original);
      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsNothing,
      );
      host.policyState = 'match';
      host.detected = 'Pilot_Alpha';
      await composition.account.refresh();
      await composition.gameLog!.run();
      await _finishReads(tester);
      expect(composition.handleMismatch.notice, isNull);
      host.policyState = 'mismatch';
      host.detected = 'Pilot-Alpha';
      await composition.account.refresh();
      await composition.gameLog!.run();
      await _finishReads(tester);
      expect(composition.handleMismatch.notice!.key, original);
      expect(
        find.byKey(const ValueKey('handle-mismatch-banner')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'active bridge generation revokes old dialog before new account snapshot responds',
    (tester) async {
      final host = _MismatchHost();
      final composition = await _mount(tester, host);
      await _finishReads(tester);
      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsOneWidget,
      );
      final old = composition.handleMismatch.notice!.key;
      host.accountReadBarrier = Completer<void>();
      await host.changeOwner();
      await _finishReads(tester);
      expect(host.session.activeGeneration, 8);
      expect(
        host.requests.any(
          (r) => r.name == 'account.getCurrent' && r.sessionGeneration == 8,
        ),
        isTrue,
      );
      expect(host.accountReadBarrier!.isCompleted, isFalse);
      expect(composition.handleMismatch.isCurrent(old), isFalse);
      expect(composition.handleMismatch.notice, isNull);
      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('handle-mismatch-banner')),
        findsNothing,
      );
      host.accountReadBarrier!.complete();
      await _finishReads(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'background A request receipt for actual B deduplicates B across foreground return',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final host = _MismatchHost()
        ..firstNotificationBarrier = Completer<void>();
      final composition = await _mount(tester, host);
      await _finishReads(tester);
      expect(
        host.requests.where((r) => r.name == 'gameIdentity.notifyMismatch'),
        hasLength(1),
      );
      // First request is outstanding. The Host commits a different current
      // observation B; B's second request is suppressed by native deduplication.
      host.detected = 'Pilot_Beta';
      host.laterNotificationsSuppressed = true;
      await composition.account.refresh();
      await composition.gameLog!.run();
      await _finishReads(tester);
      expect(composition.handleMismatch.notice!.detectedHandle, 'Pilot_Beta');
      expect(
        host.requests.where((r) => r.name == 'gameIdentity.notifyMismatch'),
        hasLength(2),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _finishReads(tester);
      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsNothing,
        reason: 'Pending actual-pair receipt must settle before automatic prompting.',
      );
      host.firstNotificationBarrier!.complete();
      await _finishReads(tester);
      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsNothing,
        reason:
            'The actual submitted pair is B, not the pair cached when A began.',
      );
      expect(
        find.byKey(const ValueKey('handle-mismatch-banner')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('handle-mismatch-action')));
      await _finishReads(tester);
      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsOneWidget,
      );
      expect(find.textContaining('Pilot_Beta'), findsWidgets);
    },
  );

  testWidgets(
    'R9 Pilot_Alpha vs Pilot-Alpha remains actionable across real shell pages',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final host = _MismatchHost();
      final preferences = InMemoryAppPreferences(
        initial: AppPreferences.defaults.copyWith(
          motionPreference: MotionPreference.reduce,
        ),
      );
      final navigation = ValueNotifier<OpenDestinationIntent?>(null);
      final composition = AppComposition.forConnectedProduct(
        nativeHost: host,
        preferences: preferences,
        windowChrome: InMemoryWindowChrome(),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(host.close);
        navigation.dispose();
        preferences.dispose();
      });

      // Exercise the product composition, real AccountModule/Bridge adapter and
      // real GameLogController. Only the Host transport is an in-memory fixture.
      await tester.pumpWidget(
        StarBridgeApp(composition: composition, navigationRequests: navigation),
      );
      await _finishReads(tester);
      expect(find.byType(StarBridgeShell), findsOneWidget);
      expect(composition.account.projection.value.failure, isNull);
      expect(
        composition.account.projection.value.identity.state,
        AccountIdentityState.mismatch,
      );
      expect(
        composition.account.projection.value.identity.authoritativeHandle,
        'Pilot_Alpha',
      );
      expect(composition.gameLog!.value.error, isNull);
      expect(composition.gameLog!.value.state, 'identified');
      expect(composition.gameLog!.value.expectedHandle, 'Pilot_Alpha');
      expect(composition.gameLog!.value.handle, 'Pilot-Alpha');
      expect(composition.gameLog!.value.match, 'mismatch');
      expect(find.byType(SettingsPage), findsNothing);
      expect(tester.takeException(), isNull);

      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('handle-mismatch-later')));
      await _finishReads(tester);
      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsNothing,
      );

      final noticesByPage = <String, (int, int)>{};
      (int, int) noticeCounts() => (
        find.byKey(const ValueKey('handle-mismatch-banner')).evaluate().length,
        find.byKey(const ValueKey('handle-mismatch-action')).evaluate().length,
      );
      noticesByPage['home'] = noticeCounts();

      navigation.value = const OpenDestinationIntent('/friends');
      await _finishReads(tester);
      expect(find.byType(FriendsPage), findsOneWidget);
      expect(find.byType(SettingsPage), findsNothing);
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('handle-mismatch-dialog')),
        findsNothing,
      );
      noticesByPage['friends'] = noticeCounts();

      expect(
        host.requests.where((request) => request.name == 'gameLog.read'),
        isNotEmpty,
      );
      expect(
        host.requests.where(
          (request) =>
              request.name == 'account.logout' ||
              request.name == 'account.login' ||
              request.name.toLowerCase().contains('rename'),
        ),
        isEmpty,
        reason: 'Reading a mismatch must not perform account mutations.',
      );
      expect(
        noticesByPage,
        {'home': (1, 1), 'friends': (1, 1)},
        reason:
            'A confirmed Handle mismatch must remain visible and actionable '
            'outside account settings; underscore and hyphen are not equivalent.',
      );
    },
  );
}

Future<AppComposition> _mount(
  WidgetTester tester,
  _MismatchHost host, {
  StartupPromptQueue? queue,
  GlobalKey<NavigatorState>? navigator,
  bool Function()? ready,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final preferences = InMemoryAppPreferences(
    initial: AppPreferences.defaults.copyWith(
      motionPreference: MotionPreference.reduce,
    ),
  );
  final composition = AppComposition.forConnectedProduct(
    nativeHost: host,
    preferences: preferences,
    windowChrome: InMemoryWindowChrome(),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(host.close);
    preferences.dispose();
  });
  await tester.pumpWidget(
    StarBridgeApp(
      composition: composition,
      promptQueue: queue,
      navigatorKey: navigator,
      canPresentIdentityPrompt: ready,
    ),
  );
  return composition;
}

Future<void> _finishReads(WidgetTester tester) async {
  // Bound the loop instead of waiting for periodic product polls to settle.
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final class _MismatchHost implements NativeHostLease {
  _MismatchHost() {
    session =
        BridgeClientSession(connection: _pair.client, sessionGeneration: 7)
          ..acceptHostCapabilities([
            'account.read',
            'gameLog.local',
            'gameIdentity.prepareHandleChange',
            'gameIdentity.confirmHandleChange',
            'gameIdentity.cancelHandleChange',
            'gameIdentity.notifyMismatch',
            'notificationSettings.consumeActivation',
          ]);
    _subscription = _pair.host.incoming.listen(_respond);
  }

  final _pair = InMemoryBridgeConnection.createPair();
  final requests = <BridgeEnvelope>[];
  final _termination = Completer<NativeHostTermination>();
  late final StreamSubscription<BridgeEnvelope> _subscription;
  @override
  late final BridgeClientSession session;
  bool _closed = false;
  String? detected = 'Pilot-Alpha';
  String policyState = 'mismatch',
      prepareState = 'unknown',
      accountState = 'legacySignedIn';
  bool submitted = true;
  bool writable = false;
  String expected = 'Pilot_Alpha';
  int sequence = 0;
  Completer<void>? accountReadBarrier, firstNotificationBarrier;
  int notificationCount = 0;
  bool laterNotificationsSuppressed = false;

  Future<void> activate() => _pair.host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'event',
      name: 'notificationSettings.activated',
      sessionGeneration: session.activeGeneration,
      sequence: sequence++,
      payload: {'schemaVersion': 1, 'activationId': 'd' * 32},
    ),
  );

  Future<void> changeOwner() async {
    accountState = 'signedOut';
    policyState = 'unknown';
    detected = null;
    await _pair.host.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.changed',
        sessionGeneration: 8,
        sequence: sequence++,
        payload: const {'schemaVersion': 1},
      ),
    );
  }

  static const _owner = BridgeAccountContext(
    environment: 'test',
    authority: 'starbridge-relay-synthetic',
    subject: 'synthetic-handle-mismatch-owner',
  );

  @override
  Future<NativeHostTermination> get terminated => _termination.future;

  Future<void> _respond(BridgeEnvelope request) async {
    if (_closed || request.name == 'bridge.cancel') return;
    requests.add(request);
    if (request.name == 'account.getCurrent' && request.sessionGeneration > 7) {
      await accountReadBarrier?.future;
    }
    var actuallySubmitted = submitted;
    if (request.name == 'gameIdentity.notifyMismatch') {
      final index = ++notificationCount;
      if (index == 1) await firstNotificationBarrier?.future;
      actuallySubmitted =
          submitted && !(laterNotificationsSuppressed && index > 1);
    }
    if (_closed) return;
    final Map<String, Object?>? payload = switch (request.name) {
      'account.getCurrent' => {
        'schemaVersion': 1,
        'state': accountState,
        'displayName': 'Synthetic Pilot',
      },
      'gameIdentity.getPolicy' => {
        'schemaVersion': 1,
        'state': policyState,
        'sensitiveWritesAllowed': false,
        'authoritativeHandle': expected,
        'detectedHandle': detected,
        'scmBindingState': 'unknown',
      },
      'gameIdentity.prepareHandleChange' => {
        'schemaVersion': 1,
        'state': prepareState,
        'expectedHandle': expected,
        'detectedHandle': detected,
        'scmBindingState': 'unknown',
        if (writable) 'mode': 'legacyCompatibility',
        if (writable && prepareState == 'ready') 'confirmationId': 'a' * 32,
      },
      'gameIdentity.confirmHandleChange' => {
        'schemaVersion': 1,
        'outcome': 'confirmed',
      },
      'gameIdentity.cancelHandleChange' => {
        'schemaVersion': 1,
        'cancelled': true,
      },
      'gameIdentity.notifyMismatch' => {
        'schemaVersion': 1,
        'submitted': actuallySubmitted,
        'reason': actuallySubmitted ? 'submitted' : 'disabled',
        if (actuallySubmitted) 'authoritativeHandle': 'Pilot_Alpha',
        if (actuallySubmitted) 'detectedHandle': detected,
      },
      'notificationSettings.consumeActivation' => {
        'schemaVersion': 1,
        'destination': 'gameIdentity',
      },
      'gameLog.read' => {
        'schemaVersion': 1,
        'state': detected == null ? 'notRunning' : 'identified',
        'enabled': true,
        'channel': 'LIVE',
        'selection': 'automatic',
        'channels': ['LIVE'],
        'verifiedChannels': <String>[],
        'handle': detected,
        'expectedHandle': expected,
        'match': detected == null ? 'unknown' : policyState,
        'session': {
          'schemaVersion': 1,
          'state': 'unavailable',
          'server': {'state': 'unknown'},
          'location': {'state': 'unknown', 'names': <String, Object?>{}},
          'ship': {'state': 'unknown', 'names': <String, Object?>{}},
        },
      },
      _ => null,
    };
    await _pair.host.send(
      BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'response',
        name: request.name,
        correlationId: request.correlationId,
        sessionGeneration: request.sessionGeneration,
        accountContext: _owner,
        status: payload == null ? 'error' : 'ok',
        payload: payload ?? const {},
        error: payload == null
            ? const BridgeErrorBody(
                code: 'bridge.capability_unavailable',
                message: 'Unrelated capability is outside this fixture.',
                retryable: false,
              )
            : null,
      ),
    );
    if (request.name == 'gameIdentity.confirmHandleChange' && writable) {
      expected = detected!;
      policyState = 'match';
      await _pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.changed',
          sessionGeneration: 8,
          sequence: sequence++,
          payload: const {'schemaVersion': 1},
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await session.close();
    await _pair.host.close();
  }
}
