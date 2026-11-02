import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_exec_hangar_window.dart';
import 'package:starbridge_flutter/features/tools/exec_hangar_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/window/menu_exec_hangar_game_overlay.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

import '../../features/tools/exec_hangar_test.dart' show app, captureHangar;
import '../../features/friends/social_layout_test.dart' show size, loadFonts;
import 'menu_exec_hangar_widget_test.dart' show SummaryPort;

class GamePort extends SummaryPort implements MenuExecHangarGameOverlayPort {
  @override
  bool get gameOverlayAvailable => true;
  MenuExecHangarGameState state = const MenuExecHangarGameState(
    false,
    MenuExecHangarGamePosition.topLeft,
  );
  final calls = <String>[];
  bool fail = false;
  Completer<MenuExecHangarGameState>? pendingOverlay;
  @override
  Future<MenuExecHangarGameState> readGameOverlay() async {
    calls.add('read');
    if (fail) throw StateError('unavailable');
    return pendingOverlay?.future ?? state;
  }

  @override
  Future<MenuExecHangarGameState> pinToGame(
    MenuExecHangarGamePosition position,
  ) async {
    calls.add('pin:${position.name}');
    if (fail) throw StateError('unavailable');
    return state = MenuExecHangarGameState(true, position);
  }

  @override
  Future<MenuExecHangarGameState> unpinFromGame() async {
    calls.add('unpin');
    if (fail) throw StateError('unavailable');
    return state = MenuExecHangarGameState(false, state.position);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real Host port sends only exact session-owned display requests',
    () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 3,
      );
      final port = BridgeExecHangar(session);
      expect(port.gameOverlayAvailable, isFalse);
      await expectLater(
        port.readGameOverlay(),
        throwsA(isA<BridgeFormatException>()),
      );
      session.acceptHostCapabilities(const [
        'execHangar.gameOverlay.read',
        'execHangar.gameOverlay.pin',
        'execHangar.gameOverlay.unpin',
      ]);
      expect(port.gameOverlayAvailable, isTrue);
      final requests = <BridgeEnvelope>[];
      var state = const MenuExecHangarGameState(
        false,
        MenuExecHangarGamePosition.topLeft,
      );
      final subscription = pair.host.incoming.listen((request) async {
        requests.add(request);
        if (request.name.endsWith('.pin')) {
          state = MenuExecHangarGameState(
            true,
            MenuExecHangarGamePosition.bottomCenter,
          );
        } else if (request.name.endsWith('.unpin')) {
          state = MenuExecHangarGameState(false, state.position);
        }
        await pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            payload: state.toMap(),
            status: 'ok',
          ),
        );
      });
      try {
        expect((await port.readGameOverlay()).pinned, isFalse);
        expect(
          (await port.pinToGame(MenuExecHangarGamePosition.bottomCenter))
              .pinned,
          isTrue,
        );
        expect((await port.unpinFromGame()).pinned, isFalse);
        expect(requests.map((r) => r.name), [
          'execHangar.gameOverlay.read',
          'execHangar.gameOverlay.pin',
          'execHangar.gameOverlay.unpin',
        ]);
        expect(requests.map((r) => r.payload), [
          {'schemaVersion': 1},
          {'schemaVersion': 1, 'position': 'bottomCenter'},
          {'schemaVersion': 1},
        ]);
        expect(
          requests.every(
            (r) => r.accountContext == null && r.sessionGeneration == 3,
          ),
          isTrue,
        );
      } finally {
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      }
    },
  );
  test('six exact positions and strict display state parser', () {
    for (final position in MenuExecHangarGamePosition.values) {
      expect(
        MenuExecHangarGameState.parse(
          MenuExecHangarGameState(true, position).toMap(),
        ).position,
        position,
      );
    }
    for (final raw in [
      null,
      {'schemaVersion': 1.0, 'pinned': true, 'position': 'topLeft'},
      {'schemaVersion': 1, 'pinned': true, 'position': 'center'},
      {
        'schemaVersion': 1,
        'pinned': true,
        'position': 'topLeft',
        'enabled': true,
      },
    ]) {
      expect(() => MenuExecHangarGameState.parse(raw), throwsFormatException);
    }
  });
  for (final position in MenuExecHangarGamePosition.values) {
    testWidgets('choose ${position.name} before pinning and cancel from menu', (
      tester,
    ) async {
      size(tester, const Size(500, 800));
      final port = GamePort();
      await tester.pumpWidget(
        app(
          MenuExecHangarWindow(port: port, active: true, pinned: false),
          const Locale('zh', 'CN'),
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-hangar-game-pin')));
      await tester.pumpAndSettle();
      expect(port.calls, ['read']);
      await tester.tap(
        find.byKey(ValueKey('menu-hangar-game-${position.name}')),
      );
      await tester.pumpAndSettle();
      expect(port.state.pinned, false);
      await tester.tap(find.byKey(const Key('menu-hangar-game-confirm')));
      await tester.pumpAndSettle();
      expect(port.state.pinned, true);
      expect(port.state.position, position);
      expect(port.calls, ['read', 'pin:${position.name}']);
      expect(find.byKey(const Key('menu-hangar-game-confirm')), findsNothing);
      await tester.tap(find.byKey(const Key('menu-hangar-game-pin')));
      await tester.pumpAndSettle();
      expect(port.state.pinned, false);
      expect(port.calls.last, 'unpin');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'cancelling position chooser does not pin; reopening reads current game pin',
    (tester) async {
      size(tester, const Size(600, 900));
      final port = GamePort();
      Widget menu() => app(
        MenuExecHangarWindow(port: port, active: true, pinned: false),
        const Locale('zh', 'CN'),
        AppearanceMode.dark,
      );
      await tester.pumpWidget(menu());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-hangar-game-pin')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-hangar-game-cancel')));
      await tester.pumpAndSettle();
      expect(port.calls, ['read']);
      expect(port.state.pinned, false);
      port.state = const MenuExecHangarGameState(
        true,
        MenuExecHangarGamePosition.bottomLeft,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(menu());
      await tester.pumpAndSettle();
      expect(find.text('取消游戏固定'), findsOneWidget);
      expect(find.text('已固定到游戏 · 左下'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('failed pin remains in chooser and never claims shown', (
    tester,
  ) async {
    size(tester, const Size(600, 900));
    final port = GamePort();
    await tester.pumpWidget(
      app(
        MenuExecHangarWindow(port: port, active: true, pinned: false),
        const Locale('zh', 'CN'),
        AppearanceMode.dark,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-hangar-game-pin')));
    await tester.pumpAndSettle();
    port.fail = true;
    await tester.tap(find.byKey(const Key('menu-hangar-game-confirm')));
    await tester.pumpAndSettle();
    expect(port.state.pinned, false);
    expect(find.text('已固定到游戏'), findsNothing);
    expect(find.text('未能确认游戏浮层状态，请重试。'), findsOneWidget);
    expect(find.byKey(const Key('menu-hangar-game-confirm')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en', 'US'),
  ]) {
    testWidgets('position chooser $locale large text and visual capture', (
      tester,
    ) async {
      size(tester, const Size(520, 900));
      await tester.runAsync(loadFonts);
      final visual = GlobalKey();
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.5)),
              child: RepaintBoundary(
                key: visual,
                child: MenuExecHangarWindow(
                  port: GamePort(),
                  active: true,
                  pinned: false,
                ),
              ),
            ),
          ),
          locale,
          AppearanceMode.dark,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-hangar-game-pin')));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(6));
      expect(tester.takeException(), isNull);
      if (locale.countryCode == 'CN') {
        await captureHangar(
          tester,
          visual,
          'exec-hangar-game-position-chooser',
        );
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  test('primary bridge rejects invalid or stale menu display intents without Host calls', () async {
    final port = GamePort();
    bool current = true;
    Future<String> request(Object? arguments) =>
        MenuExecHangarGameOverlayRequest.handle(
          arguments: arguments,
          opening: 7,
          isCurrent: () => current,
          port: port,
        );
    for (final args in [
      null,
      {'opening': 6, 'action': 'read'},
      {'opening': 7.0, 'action': 'read'},
      {'opening': 7, 'action': 'stop'},
      {'opening': 7, 'action': 'pin', 'position': 'center'},
      {'opening': 7, 'action': 'pin', 'position': 'topLeft', 'payload': '{}'},
      {'opening': 7, 'action': 'read', 'path': 'C:/private'},
    ]) {
      await expectLater(request(args), throwsA(isA<PlatformException>()));
    }
    expect(port.calls, isEmpty);
    await request({'opening': 7, 'action': 'pin', 'position': 'bottomRight'});
    expect(port.calls, ['pin:bottomRight']);
    port.pendingOverlay = Completer<MenuExecHangarGameState>();
    final pendingOverlay = request({'opening': 7, 'action': 'read'});
    current = false;
    port.pendingOverlay!.complete(port.state);
    await expectLater(pendingOverlay, throwsA(isA<PlatformException>()));
  });
  test(
    'surface channel emits exact display intents and rejects late state',
    () async {
      const channel = MethodChannel('game-overlay-test');
      bool current = true;
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return jsonEncode(
          const MenuExecHangarGameState(
            true,
            MenuExecHangarGamePosition.topCenter,
          ).toMap(),
        );
      });
      final port = SurfaceMenuExecHangarGameOverlay(channel, 8, () => current);
      expect(
        (await port.pinToGame(MenuExecHangarGamePosition.topCenter)).position,
        MenuExecHangarGamePosition.topCenter,
      );
      expect(calls.single.method, 'execHangarGameOverlay');
      expect(calls.single.arguments, {
        'opening': 8,
        'action': 'pin',
        'position': 'topCenter',
      });
      await port.unpinFromGame();
      expect(calls.last.arguments, {'opening': 8, 'action': 'unpin'});
      current = false;
      await expectLater(
        port.readGameOverlay(),
        throwsA(isA<PlatformException>()),
      );
      expect(calls.length, 2);
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
}
