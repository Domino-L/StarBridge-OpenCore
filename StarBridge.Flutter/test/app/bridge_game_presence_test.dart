import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/bridge_game_presence.dart';
import 'package:starbridge_flutter/features/game_log/game_log_controller.dart';
import 'package:starbridge_flutter/app/composition/account_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/in_memory_shell_chrome.dart';
import 'package:starbridge_flutter/app/shell/chrome/shell_chrome_projection.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

void main() {
  testWidgets('old Host stays unknown without an unsupported request', (
    tester,
  ) async {
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 0,
    );
    var requests = 0;
    final subscription = pair.host.incoming.listen((_) => requests++);
    final source = BridgeGamePresence(session);
    await tester.pump(const Duration(seconds: 30));
    expect(source.value, GamePresenceState.unknown);
    expect(requests, 0);
    source.dispose();
    await tester.runAsync(() async {
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    });
  });

  testWidgets(
    'local observation polls, fails unknown, recovers and stops on disposal',
    (tester) async {
      final pair = InMemoryBridgeConnection.createPair();
      final session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 0,
      )..acceptHostCapabilities(['host.gamePresence']);
      var state = 'running';
      var version = 'EPTU';
      var respond = true;
      var reads = 0;
      final subscription = pair.host.incoming.listen((request) {
        if (request.name == 'bridge.cancel') return;
        expectSync(request.name, 'host.getGamePresence');
        expectSync(request.accountContext, isNull);
        reads++;
        if (!respond) return;
        unawaited(
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: request.sessionGeneration,
              payload: {'schemaVersion': 1, 'state': state, 'version': version},
              status: 'ok',
            ),
          ),
        );
      });
      final source = BridgeGamePresence(session);
      await tester.pump();
      expect(source.value, GamePresenceState.running);
      expect(source.version, 'EPTU');
      state = 'notRunning';
      await tester.pump(const Duration(seconds: 5));
      expect(source.value, GamePresenceState.notRunning);
      expect(source.version, isNull);
      respond = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(source.value, GamePresenceState.unknown);
      respond = true;
      state = 'running';
      version = 'HOTFIX';
      await tester.pump(const Duration(seconds: 5));
      expect(source.value, GamePresenceState.running);
      expect(source.version, 'HOTFIX');
      version = '../EPTU';
      await tester.pump(const Duration(seconds: 5));
      expect(source.value, GamePresenceState.running);
      expect(source.version, isNull);
      state = 'invented-status';
      await tester.pump(const Duration(seconds: 5));
      expect(source.value, GamePresenceState.unknown);
      source.dispose();
      final finalReads = reads;
      await tester.pump(const Duration(seconds: 30));
      expect(reads, finalReads);
      await tester.runAsync(() async {
        await subscription.cancel();
        await session.close();
        await pair.host.close();
      });
    },
  );

  test(
    'application connectivity and local game state do not overwrite each other',
    () async {
      final account = createAccountModule(
        InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
      );
      final source = ValueNotifier(GamePresenceState.unknown);
      final gameLog = ValueNotifier(
        const GameLogView(
          visible: true,
          enabled: true,
          state: 'waiting',
          channel: 'EPTU',
          channels: ['LIVE', 'PTU', 'EPTU'],
        ),
      );
      final base = InMemoryShellChrome(
        initial: InMemoryShellChrome.hostConnectedProjection,
      );
      final chrome = AccountShellChrome(
        base: base,
        account: account,
        gamePresence: source,
        gameLog: gameLog,
      );
      addTearDown(() {
        chrome.dispose();
        source.dispose();
        gameLog.dispose();
        account.dispose();
      });
      expect(chrome.projection.value.presenceKey, 'presence.unknown');
      await account.initialize();
      expect(chrome.projection.value.presenceKey, 'presence.online');
      expect(chrome.projection.value.gamePresence, GamePresenceState.unknown);
      source.value = GamePresenceState.running;
      expect(chrome.projection.value.displayPresenceKey, 'presence.inGame');
      expect(chrome.projection.value.gameVersion, isNull);
      gameLog.value = const GameLogView(
        visible: true,
        enabled: true,
        state: 'identified',
        match: 'match',
        channel: 'EPTU',
        channels: ['LIVE', 'PTU', 'EPTU'],
        verifiedChannels: ['EPTU'],
      );
      expect(chrome.projection.value.gameVersion, 'EPTU');
      expect(chrome.projection.value.presenceKey, 'presence.online');
      base.replace(InMemoryShellChrome.disconnectedProjection);
      expect(chrome.projection.value.presenceKey, 'presence.unknown');
      expect(chrome.projection.value.gamePresence, GamePresenceState.running);
      source.value = GamePresenceState.notRunning;
      expect(chrome.projection.value.displayPresenceKey, 'presence.unknown');
      expect(chrome.projection.value.gameVersion, isNull);
      source.value = GamePresenceState.running;
      gameLog.value = const GameLogView(
        visible: true,
        enabled: true,
        state: 'identified',
        match: 'mismatch',
        channel: 'HOTFIX',
        channels: ['LIVE', 'HOTFIX'],
        verifiedChannels: ['HOTFIX'],
      );
      expect(chrome.projection.value.gameVersion, isNull);
    },
  );
}
