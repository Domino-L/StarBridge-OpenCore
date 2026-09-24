import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';

import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'package:starbridge_flutter/features/game_log/game_log_controller.dart';
import 'package:starbridge_flutter/features/settings/local_game_recognition_dialog.dart';

void main() {
  testWidgets('real dialog route shows existing game information and closes', (
    tester,
  ) async {
    final h = _Harness(AccountSessionState.legacySignedIn);
    addTearDown(h.close);
    await tester.pumpWidget(_app(h.controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('game-session-overview')), findsOneWidget);
    expect(find.byKey(const Key('game-session-identity')), findsOneWidget);
    expect(h.controller.value.handle, 'SyntheticPilot');
    expect(find.textContaining('SyntheticPilot'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('local-game-recognition-refresh')));
    await tester.pumpAndSettle();
    expect(h.requests.where((r) => r.name == 'gameLog.read').length, 2);
    await tester.tap(find.byKey(const Key('settings-entry-close')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-entry-local-game-recognition')),
      findsNothing,
    );
    expect(h.controller.value.state, 'identified');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(h.close);
  });

  testWidgets('open dialog removes personal game details on logout', (
    tester,
  ) async {
    final h = _Harness(AccountSessionState.legacySignedIn);
    addTearDown(h.close);
    await tester.pumpWidget(_app(h.controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    h.account.value = h.account.value.copyWith(
      sessionState: AccountSessionState.signedOut,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('SyntheticPilot'), findsNothing);
    expect(find.byKey(const Key('game-session-overview')), findsNothing);
    expect(
      find.byKey(const Key('local-game-recognition-unavailable')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('local-game-recognition-refresh')),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(h.close);
  });

  testWidgets('missing host keeps the entry available without fake controls', (
    tester,
  ) async {
    await tester.pumpWidget(_app(null));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settings-entry-local-game-recognition')),
      findsOneWidget,
    );
    expect(find.text('暂时无法读取游戏识别信息。'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const Key('local-game-recognition-refresh')),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    for (final mode in [AppearanceMode.dark, AppearanceMode.light]) {
      testWidgets('real populated dialog fits 390px $locale $mode', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final h = _Harness(AccountSessionState.legacySignedIn);
        addTearDown(h.close);
        await tester.pumpWidget(_app(h.controller, locale: locale, mode: mode));
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('game-session-overview')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('settings-entry-close')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('settings-entry-local-game-recognition')),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(h.close);
      });
    }
  }
  testWidgets('legacy login reads and displays its real game session', (
    tester,
  ) async {
    final h = _Harness(AccountSessionState.legacySignedIn);
    addTearDown(h.close);
    await tester.pump();
    expect(h.controller.value.visible, isTrue);
    expect(h.controller.value.state, 'identified');
    expect(h.controller.value.handle, 'SyntheticPilot');
    expect(h.controller.value.serverRegion, 'US');
    expect(h.requests.map((r) => r.name), [
      'account.getCurrent',
      'gameLog.read',
    ]);
    expect(
      h.requests.last.accountContext?.authority,
      'starbridge-relay-synthetic',
    );
    await tester.runAsync(h.close);
  });

  testWidgets('SCM login still reads with its own authority', (tester) async {
    final h = _Harness(AccountSessionState.signedIn);
    addTearDown(h.close);
    await tester.pump();
    expect(h.controller.value.state, 'identified');
    expect(h.requests.last.accountContext?.authority, 'scm');
    await tester.runAsync(h.close);
  });

  for (final state in AccountSessionState.values.where(
    (s) =>
        s != AccountSessionState.signedIn &&
        s != AccountSessionState.legacySignedIn,
  )) {
    testWidgets('$state never requests or displays another account game data', (
      tester,
    ) async {
      final h = _Harness(state);
      addTearDown(h.close);
      await tester.pump();
      expect(h.controller.value.visible, isFalse);
      expect(h.controller.value.handle, isNull);
      expect(h.requests, isEmpty);
      await tester.runAsync(h.close);
    });
  }

  testWidgets('legacy account still requires gameLog capability', (
    tester,
  ) async {
    final h = _Harness(AccountSessionState.legacySignedIn, supported: false);
    addTearDown(h.close);
    await tester.pump();
    expect(h.controller.value.visible, isTrue);
    expect(h.controller.value.error, 'unsupported');
    expect(h.requests, isEmpty);
    await tester.runAsync(h.close);
  });

  testWidgets('signed-in kind mismatch in account reply is rejected', (
    tester,
  ) async {
    final h = _Harness(AccountSessionState.legacySignedIn)
      ..responseState = 'signedIn';
    addTearDown(h.close);
    await tester.pump();
    expect(h.controller.value.error, 'unavailable');
    expect(h.controller.value.handle, isNull);
    expect(h.requests.map((r) => r.name), ['account.getCurrent']);
    await tester.runAsync(h.close);
  });

  testWidgets('unavailable legacy account reply cannot grant local access', (
    tester,
  ) async {
    final h = _Harness(AccountSessionState.legacySignedIn)
      ..responseState = 'legacyUnavailable';
    addTearDown(h.close);
    await tester.pump();
    expect(h.controller.value.error, 'unavailable');
    expect(h.requests.map((r) => r.name), ['account.getCurrent']);
    await tester.runAsync(h.close);
  });

  testWidgets('wrong owner game data is rejected', (tester) async {
    final h = _Harness(AccountSessionState.legacySignedIn)..wrongOwner = true;
    addTearDown(h.close);
    await tester.pump();
    expect(h.controller.value.error, 'unavailable');
    expect(h.controller.value.handle, isNull);
    expect(h.controller.value.serverRegion, isNull);
    await tester.runAsync(h.close);
  });

  testWidgets('legacy picker result is discarded after logout', (tester) async {
    final h = _Harness(AccountSessionState.legacySignedIn);
    addTearDown(h.close);
    await tester.pump();
    final pick = Completer<String?>();
    final operation = h.controller.pick(() => pick.future);
    h.account.value = h.account.value.copyWith(
      sessionState: AccountSessionState.signedOut,
    );
    pick.complete('C:/synthetic/Game.log');
    await tester.pump();
    await operation;
    expect(h.controller.value.visible, isFalse);
    expect(h.controller.value.handle, isNull);
    expect(h.requests.where((r) => r.name == 'gameLog.select'), isEmpty);
    await tester.runAsync(h.close);
  });

  testWidgets('generation change discards old read and uses the new owner', (
    tester,
  ) async {
    final h = _Harness(AccountSessionState.legacySignedIn)..hold = true;
    addTearDown(h.close);
    await tester.pump();
    final old = h.held!;
    h.hold = false;
    h.session.advanceGeneration(2);
    h.account.value = h.account.value.copyWith(
      sessionState: AccountSessionState.signedIn,
      generation: 2,
    );
    await tester.pump();
    h.respond(old);
    await tester.pump();
    expect(h.controller.value.visible, isTrue);
    expect(h.controller.value.state, 'identified');
    final latest = h.requests.last;
    expect(latest.sessionGeneration, 2);
    expect(latest.accountContext?.authority, 'scm');
    expect(h.controller.value.error, isNull);
    await tester.runAsync(h.close);
  });

  testWidgets('legacy unavailable transition hides data and cancels polling', (
    tester,
  ) async {
    final h = _Harness(AccountSessionState.legacySignedIn);
    addTearDown(h.close);
    await tester.pump();
    h.account.value = h.account.value.copyWith(
      sessionState: AccountSessionState.legacyUnavailable,
    );
    final count = h.requests.length;
    await tester.pump(const Duration(seconds: 4));
    expect(h.controller.value.visible, isFalse);
    expect(h.controller.value.handle, isNull);
    expect(h.controller.value.serverShard, isNull);
    expect(h.requests.length, count);
    await tester.runAsync(h.close);
  });

  testWidgets('legacy manual selection reuses existing scoped command', (
    tester,
  ) async {
    final h = _Harness(AccountSessionState.legacySignedIn);
    addTearDown(h.close);
    await tester.pump();
    final task = h.controller.pick(() async => 'C:/synthetic/Game.log');
    await tester.pump();
    await task;
    expect(h.requests.last.name, 'gameLog.select');
    expect(
      h.requests.last.accountContext?.authority,
      'starbridge-relay-synthetic',
    );
    expect(h.requests.last.payload['path'], 'C:/synthetic/Game.log');
    expect(h.controller.value.state, 'identified');
    await tester.runAsync(h.close);
  });
}

Widget _app(
  GameLogController? controller, {
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode mode = AppearanceMode.dark,
}) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, mode)
      .tokens;
  return MaterialApp(
    locale: locale,
    supportedLocales: AppStrings.runtimeSupportedLocales(),
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildStarBridgeTheme(tokens, locale),
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showLocalGameRecognitionDialog(context, controller),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

class _Harness {
  _Harness(AccountSessionState state, {bool supported = true}) {
    account = ValueNotifier(
      const AccountProjection.loading().copyWith(
        sessionState: state,
        generation: 1,
        operation: AccountOperation.none,
      ),
    );
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    if (supported) session.acceptHostCapabilities(['gameLog.local']);
    subscription = pair.host.incoming.listen((request) {
      if (request.name == 'bridge.cancel') return;
      requests.add(request);
      if (hold && request.name != 'account.getCurrent') {
        held = request;
      } else {
        respond(request);
      }
    });
    controller = GameLogController(session, account);
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final ValueNotifier<AccountProjection> account;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  late final GameLogController controller;
  final requests = <BridgeEnvelope>[];
  bool hold = false, wrongOwner = false;
  String? responseState;
  BridgeEnvelope? held;
  bool _closed = false;
  void respond(BridgeEnvelope request) {
    final state = responseState ?? account.value.sessionState.name;
    unawaited(
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: BridgeAccountContext(
            environment: 'test',
            authority: state == 'signedIn'
                ? 'scm'
                : 'starbridge-relay-synthetic',
            subject: wrongOwner && request.name != 'account.getCurrent'
                ? 'other'
                : 'synthetic-pilot',
          ),
          status: 'ok',
          payload: request.name == 'account.getCurrent'
              ? {'schemaVersion': 1, 'state': state}
              : {
                  'schemaVersion': 1,
                  'state': 'identified',
                  'enabled': true,
                  'channel': 'LIVE',
                  'selection': 'automatic',
                  'channels': ['LIVE', 'PTU'],
                  'verifiedChannels': ['LIVE'],
                  'handle': 'SyntheticPilot',
                  'expectedHandle': 'SyntheticPilot',
                  'match': 'match',
                  'session': {
                    'schemaVersion': 1,
                    'state': 'ready',
                    'server': {
                      'state': 'connected',
                      'region': 'US',
                      'shard': 'pub_use1b_12545750_070',
                    },
                    'location': {
                      'state': 'confirmed',
                      'englishName': 'Lorville',
                      'names': {'zhHans': '罗威尔'},
                    },
                    'ship': {
                      'state': 'confirmed',
                      'key': 'ANVL_Arrow',
                      'englishName': 'Arrow',
                      'names': {'zhHans': '箭矢'},
                    },
                  },
                },
        ),
      ),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    controller.dispose();
    account.dispose();
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}
