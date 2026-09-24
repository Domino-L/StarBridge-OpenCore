import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/game_log/game_log_controller.dart';
import 'package:starbridge_flutter/features/game_log/game_log_panel.dart';
import 'package:starbridge_flutter/features/game_log/game_session_overview.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../gameplay_time/gameplay_time_test.dart' as support;

class Harness {
  Harness({bool supported = true}) {
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
        return;
      }
      respond(request);
    });
    controller = GameLogController(
      session,
      account,
      onIdentityChanged: () => changes++,
    );
  }
  final pair = InMemoryBridgeConnection.createPair();
  final account = ValueNotifier(
    const AccountProjection.loading().copyWith(
      sessionState: AccountSessionState.signedIn,
      generation: 1,
      operation: AccountOperation.none,
    ),
  );
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  late final GameLogController controller;
  final requests = <BridgeEnvelope>[];
  String state = 'notFound',
      match = 'unknown',
      channel = 'LIVE',
      selection = 'automatic';
  final channels = <String>['LIVE', 'PTU'];
  final verifiedChannels = <String>[];
  String? handle, path, error, observedAtUtc;
  bool hold = false, wrongOwner = false, enabled = false;
  int changes = 0;
  BridgeEnvelope? held;
  void respond(BridgeEnvelope r) {
    if (r.name == 'gameLog.configure') {
      channel = r.payload['channel'] as String;
      if (!channels.contains(channel)) channels.add(channel);
      selection = 'automatic';
      path = null;
      handle = null;
      match = 'unknown';
      state = enabled ? 'notFound' : 'stopped';
    }
    if (r.name == 'gameLog.addVersion') {
      path = r.payload['path'] as String;
      channel = path!.split('/').reversed.skip(1).first.toUpperCase();
      if (!channels.contains(channel)) channels.add(channel);
      verifiedChannels.remove(channel);
      selection = 'automatic';
      enabled = true;
      handle = null;
      match = 'unknown';
      state = 'notRunning';
    }
    if (r.name == 'gameLog.removeVersion') {
      final removed = r.payload['channel'] as String;
      channels.remove(removed);
      verifiedChannels.remove(removed);
      if (channel == removed) {
        channel = 'LIVE';
        path = null;
        selection = 'automatic';
      }
      handle = null;
      match = 'unknown';
      state = 'notRunning';
    }
    if (r.name == 'gameLog.select' || r.name == 'gameLog.find') {
      path = 'C:/synthetic/Game.log';
      enabled = true;
      handle = 'Pilot_A';
      match = 'match';
      state = 'identified';
      selection = r.name == 'gameLog.find' ? 'automatic' : 'manual';
      if (!verifiedChannels.contains(channel)) verifiedChannels.add(channel);
    }
    if (r.name == 'gameLog.stop') {
      enabled = false;
      handle = null;
      match = 'unknown';
      state = 'stopped';
    }
    unawaited(
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: r.name,
          correlationId: r.correlationId,
          sessionGeneration: r.sessionGeneration,
          accountContext: BridgeAccountContext(
            environment: 'test',
            authority: 'scm',
            subject: wrongOwner ? 'other' : 'synthetic-a',
          ),
          status: error == null || r.name == 'account.getCurrent'
              ? 'ok'
              : 'error',
          error: error == null || r.name == 'account.getCurrent'
              ? null
              : BridgeErrorBody(
                  code: error!,
                  message: 'synthetic error',
                  retryable: true,
                ),
          payload: r.name == 'account.getCurrent'
              ? {'schemaVersion': 1, 'state': 'signedIn'}
              : {
                  'schemaVersion': 1,
                  'state': state,
                  'observedAtUtc': observedAtUtc,
                  'path': path,
                  'handle': handle,
                  'expectedHandle': 'Pilot_A',
                  'match': match,
                  'enabled': enabled,
                  'channel': channel,
                  'selection': selection,
                  'channels': channels,
                  'verifiedChannels': verifiedChannels,
                  'session': {
                    'schemaVersion': 1,
                    'state': match == 'match' ? 'ready' : 'unavailable',
                    'server': {
                      'state': match == 'match' ? 'connected' : 'unknown',
                      'region': match == 'match' ? 'US' : null,
                      'shard': match == 'match'
                          ? 'pub_use1b_12545750_070'
                          : null,
                    },
                    'location': {
                      'state': match == 'match' ? 'confirmed' : 'unknown',
                      'englishName': match == 'match' ? 'Lorville' : null,
                      'names': {
                        'zhHans': match == 'match' ? '罗威尔' : null,
                        'zhHant': null,
                      },
                    },
                    'ship': {
                      'state': match == 'match' ? 'confirmed' : 'unknown',
                      'key': match == 'match' ? 'ANVL_Arrow' : null,
                      'englishName': match == 'match' ? 'Arrow' : null,
                      'names': {
                        'zhHans': match == 'match' ? '箭矢' : null,
                        'zhHant': match == 'match' ? '箭矢' : null,
                      },
                    },
                  },
                },
        ),
      ),
    );
  }

  Future<void> close(WidgetTester tester) async {
    controller.dispose();
    account.dispose();
    await tester.runAsync(() async {
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    });
  }
}

void main() {
  testWidgets(
    'last check uses Host time and survives a failed background read',
    (tester) async {
      final h = Harness()..observedAtUtc = '2026-09-13T18:04:00Z';
      await tester.pump();
      await tester.pumpWidget(
        support.app(GameLogPanel(controller: h.controller)),
      );
      await tester.pumpAndSettle();
      final observed = DateTime.parse(h.observedAtUtc!);
      expect(h.controller.value.observedAt?.toUtc(), observed);
      expect(find.byKey(const Key('game-log-last-checked')), findsOneWidget);
      expect(find.textContaining('最近检查'), findsOneWidget);
      h.error = 'gameLog.unavailable';
      final read = h.controller.run();
      await tester.pump();
      await read;
      expect(h.controller.value.observedAt?.toUtc(), observed);
      h.account.value = h.account.value.copyWith(
        sessionState: AccountSessionState.signedOut,
      );
      await tester.pump();
      expect(h.controller.value.observedAt, isNull);
      await tester.pumpWidget(const SizedBox());
      await h.close(tester);
    },
  );
  testWidgets('signed out game overview does not pretend to keep loading', (
    tester,
  ) async {
    final h = Harness();
    await tester.pump();
    await tester.pumpWidget(
      support.app(GameSessionOverview(controller: h.controller)),
    );
    h.account.value = h.account.value.copyWith(
      sessionState: AccountSessionState.signedOut,
    );
    await tester.pumpAndSettle();
    expect(find.text('登录账号后显示本机游戏识别信息。'), findsOneWidget);
    expect(find.byKey(const Key('game-session-identity')), findsNothing);
    expect(find.text('正在读取'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await h.close(tester);
  });
  const render = bool.fromEnvironment('GAME_LOG_GOLDENS');
  setUpAll(() async {
    if (!render) return;
    for (final font in {
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  testWidgets('normal detection, loading, stop and scoped commands', (
    tester,
  ) async {
    final h = Harness();
    await tester.pump();
    expect(h.controller.value.state, 'notFound');
    h.hold = true;
    final task = h.controller.run(command: 'find');
    await tester.pump();
    expect(h.controller.value.busy, isTrue);
    h.hold = false;
    h.respond(h.held!);
    await tester.pump();
    await task;
    expect(h.controller.value.match, 'match');
    expect(h.changes, 1);
    final stop = h.controller.run(command: 'stop');
    await tester.pump();
    await stop;
    expect(h.controller.value.enabled, isFalse);
    expect(h.controller.value.handle, isNull);
    expect(
      h.requests
          .where((r) => r.name.startsWith('gameLog.'))
          .every((r) => r.accountContext != null),
      isTrue,
    );
    await h.close(tester);
  });
  testWidgets(
    'remote error is useful and polling does not erase action failure',
    (tester) async {
      final h = Harness();
      await tester.pump();
      h.error = 'gameLog.notFound';
      final task = h.controller.run(command: 'find');
      await tester.pump();
      await task;
      expect(h.controller.value.error, 'notFound');
      h.error = null;
      await tester.pump(const Duration(seconds: 3));
      expect(h.controller.value.error, 'notFound');
      final retry = h.controller.run(command: 'retry');
      await tester.pump();
      await retry;
      expect(h.controller.value.error, isNull);
      await h.close(tester);
    },
  );
  testWidgets('late picker result cannot configure another account', (
    tester,
  ) async {
    final h = Harness();
    await tester.pump();
    final picker = Completer<String?>();
    final task = h.controller.pick(() => picker.future);
    h.session.advanceGeneration(2);
    h.account.value = h.account.value.copyWith(
      generation: 2,
      sessionState: AccountSessionState.signedOut,
    );
    picker.complete('C:/synthetic/Game.log');
    await tester.pump();
    await task;
    expect(h.controller.value.visible, isFalse);
    expect(h.requests.where((r) => r.name == 'gameLog.select'), isEmpty);
    await h.close(tester);
  });
  testWidgets('wrong owner clears visible identity', (tester) async {
    final h = Harness();
    await tester.pump();
    h.wrongOwner = true;
    await tester.pump(const Duration(seconds: 3));
    expect(h.controller.value.error, 'unavailable');
    expect(h.controller.value.handle, isNull);
    await h.close(tester);
  });
  testWidgets('unsupported host does not send requests', (tester) async {
    final h = Harness(supported: false);
    await tester.pump();
    expect(h.controller.value.error, 'unsupported');
    expect(h.requests, isEmpty);
    await h.close(tester);
  });
  testWidgets('game session overview remains visible without local detection', (
    tester,
  ) async {
    await tester.pumpWidget(support.app(const GameSessionOverview()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('game-session-overview')), findsOneWidget);
    expect(find.text('暂时无法读取'), findsNWidgets(2));
    expect(find.text('等待服务器信息'), findsOneWidget);
    expect(find.text('等待区域代码'), findsOneWidget);
  });
  testWidgets('LIVE default and PTU selection are explicit, scoped and busy', (
    tester,
  ) async {
    final h = Harness();
    await tester.pump();
    await tester.pumpWidget(
      support.app(GameLogPanel(controller: h.controller)),
    );
    await tester.pumpAndSettle();
    expect(h.controller.value.channel, 'LIVE');
    expect(h.controller.value.selection, 'automatic');
    expect(
      tester
          .widget<InputChip>(find.widgetWithText(InputChip, 'LIVE 正式版'))
          .selected,
      isTrue,
    );
    h.hold = true;
    await tester.tap(find.text('PTU 测试版'));
    await tester.pump();
    expect(h.controller.value.busy, isTrue);
    expect(h.held!.name, 'gameLog.configure');
    expect(h.held!.payload['channel'], 'PTU');
    expect(h.held!.accountContext, isNotNull);
    expect(
      tester
          .widget<InputChip>(find.widgetWithText(InputChip, 'LIVE 正式版'))
          .onSelected,
      isNull,
    );
    h.hold = false;
    h.respond(h.held!);
    await tester.pump();
    expect(h.controller.value.channel, 'PTU');
    expect(
      tester
          .widget<InputChip>(find.widgetWithText(InputChip, 'PTU 测试版'))
          .selected,
      isTrue,
    );
    await tester.pumpWidget(
      support.app(
        GameLogPanel(
          controller: h.controller,
          pickLog: () async => 'C:/StarCitizen/HOTFIX/Game.log',
        ),
      ),
    );
    await tester.tap(find.text('添加版本'));
    await tester.pumpAndSettle();
    expect(h.controller.value.channel, 'HOTFIX');
    expect(h.controller.value.channels, contains('HOTFIX'));
    expect(h.controller.value.verifiedChannels, isNot(contains('HOTFIX')));
    expect(find.textContaining('确认 Handle'), findsOneWidget);
    final hotfix = tester.widget<InputChip>(
      find.widgetWithText(InputChip, 'HOTFIX'),
    );
    hotfix.onDeleted!();
    await tester.pumpAndSettle();
    expect(find.text('移除 HOTFIX？'), findsOneWidget);
    expect(find.textContaining('不会删除游戏文件'), findsOneWidget);
    await tester.tap(find.text('移除版本'));
    await tester.pumpAndSettle();
    expect(h.controller.value.channels, isNot(contains('HOTFIX')));
    expect(h.controller.value.channel, 'LIVE');
    await tester.pumpWidget(const SizedBox());
    await h.close(tester);
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    for (final width in [360.0, 1100.0]) {
      testWidgets('recognition panel wraps at $width in $locale', (
        tester,
      ) async {
        final h = Harness();
        await tester.pump();
        final task = h.controller.run(command: 'find');
        await tester.pump();
        await task;
        await tester.binding.setSurfaceSize(Size(width, 1000));
        await tester.pumpWidget(
          support.app(
            GameLogPanel(controller: h.controller, pickLog: () async => null),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.textContaining('Pilot_A'), findsNWidgets(2));
        expect(find.byKey(const Key('game-session-overview')), findsNothing);
        if (render && locale.countryCode == 'CN') {
          await expectLater(
            find.byType(GameLogPanel),
            matchesGoldenFile('goldens/game-log-${width.toInt()}.png'),
          );
        }
        await tester.pumpWidget(const SizedBox());
        await h.close(tester);
        await tester.binding.setSurfaceSize(null);
      });
    }
  }
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    for (final width in [360.0, 640.0, 1100.0]) {
      testWidgets(
        'persistent game session overview wraps at $width in $locale',
        (tester) async {
          final h = Harness();
          await tester.pump();
          final task = h.controller.run(command: 'find');
          await tester.pump();
          await task;
          await tester.binding.setSurfaceSize(Size(width, 1000));
          await tester.pumpWidget(
            support.app(
              SingleChildScrollView(
                child: GameSessionOverview(controller: h.controller),
              ),
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('game-session-overview')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('game-session-state')), findsOneWidget);
          expect(find.byKey(const Key('game-session-version')), findsOneWidget);
          expect(
            find.byKey(const Key('game-session-identity')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('game-session-server')), findsOneWidget);
          expect(
            find.byKey(const Key('game-session-server-area')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('game-session-location')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('game-session-ship')), findsOneWidget);
          expect(find.textContaining('Pilot_A'), findsOneWidget);
          if (locale.countryCode == 'CN') {
            expect(find.text('游戏中'), findsNWidgets(2));
            expect(find.textContaining('LIVE 正式版'), findsOneWidget);
            expect(find.text('美服'), findsOneWidget);
            expect(find.text('pub_use1b_12545750_070'), findsOneWidget);
            expect(find.textContaining('罗威尔'), findsOneWidget);
            expect(find.textContaining('箭矢'), findsOneWidget);
          }
          if (render && locale.countryCode == 'CN') {
            await expectLater(
              find.byType(GameSessionOverview),
              matchesGoldenFile(
                'goldens/game-session-overview-${width.toInt()}.png',
              ),
            );
          }
          await tester.pumpWidget(const SizedBox());
          await h.close(tester);
          await tester.binding.setSurfaceSize(null);
        },
      );
    }
  }
}
