import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/settings/gameplay_data_export_dialog.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'settings_entry_test.dart' show app;

void main() {
  for (final state in [
    AccountSessionState.legacySignedIn,
    AccountSessionState.signedIn,
  ]) {
    testWidgets('dialog binds $state once and preserves cleanup', (
      tester,
    ) async {
      final h = _Harness(state);
      addTearDown(h.close);
      await tester.pumpWidget(h.widget());
      await tester.pumpAndSettle();
      expect(h.reads, 1);
      expect(h.exports, 0);
      await tester.pumpWidget(h.widget());
      await tester.pumpAndSettle();
      expect(
        h.reads,
        1,
        reason: 'ordinary rebuild retains the account-bound adapter',
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(
                const Key('settings-action-local-data-management-clearData'),
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('gameplay-data-export-start')));
      await tester.pumpAndSettle();
      expect(h.exports, 1);
      expect(
        h.exportOwner?.authority,
        state == AccountSessionState.legacySignedIn
            ? 'relay-fixture'
            : 'scm-fixture',
      );
      expect(find.text('游玩数据已导出。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'switching account cancels the outstanding save without success',
    (tester) async {
      final h = _Harness(AccountSessionState.legacySignedIn)..hold = true;
      addTearDown(h.close);
      await tester.pumpWidget(h.widget());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('gameplay-data-export-start')));
      await tester.pump();
      h.account.value = _projection(AccountSessionState.signedOut, 5);
      await tester.pumpAndSettle();
      expect(h.cancels, greaterThan(0));
      expect(find.text('游玩数据已导出。'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing the detail cancels its pending save', (tester) async {
    final h = _Harness(AccountSessionState.legacySignedIn)..hold = true;
    addTearDown(h.close);
    await tester.pumpWidget(h.widget());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gameplay-data-export-start')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(h.cancels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}

AccountProjection _projection(AccountSessionState state, int generation) =>
    AccountProjection(
      sessionState: state,
      operation: AccountOperation.none,
      generation: generation,
      profileFreshness: AccountProfileFreshness.unavailable,
      identity: const AccountIdentityProjection.unavailable(),
      compatibility: const AccountCompatibilityProjection.unavailable(),
      localeOptions: const [],
      timeZoneOptions: const [],
    );

class _Harness {
  _Harness(this.state) {
    account = ValueNotifier(_projection(state, 4));
    final pair = InMemoryBridgeConnection.createPair();
    host = pair.host;
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 4)
      ..acceptHostCapabilities(['gameplayTime.export']);
    subscription = host.incoming.listen((request) async {
      if (request.name == 'bridge.cancel') {
        cancels++;
        return;
      }
      if (request.messageType != 'request') return;
      final isRead = request.name == 'account.getCurrent';
      if (isRead) {
        reads++;
      } else {
        expectSync(request.name, 'gameplayTime.export');
        exports++;
        exportOwner = request.accountContext;
        if (hold) return;
      }
      await host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: 4,
          accountContext: BridgeAccountContext(
            environment: 'test',
            authority: state == AccountSessionState.legacySignedIn
                ? 'relay-fixture'
                : 'scm-fixture',
            subject: 'owner',
          ),
          status: 'ok',
          payload: isRead
              ? {'schemaVersion': 1, 'state': state.name}
              : {'schemaVersion': 1, 'outcome': 'saved'},
        ),
      );
    });
  }
  final AccountSessionState state;
  late final ValueNotifier<AccountProjection> account;
  late final BridgeClientSession session;
  late final BridgeConnection host;
  late final StreamSubscription<BridgeEnvelope> subscription;
  int reads = 0, exports = 0, cancels = 0;
  bool hold = false;
  BridgeAccountContext? exportOwner;
  final key = GlobalKey();
  Widget widget() => app(
    GameplayDataExportDialog(account: account, session: session),
    const Locale('zh', 'CN'),
    key,
  );
  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await host.close();
    account.dispose();
  }
}
