import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/settings/player_activity_controller.dart';
import 'package:starbridge_flutter/features/settings/player_activity_dialog.dart';
import 'package:starbridge_flutter/features/settings/gameplay_data_export_dialog.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';

import '../../features/settings/player_activity_test.dart' as player;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ae_test.dart' show mount;

AccountProjection projection([
  AccountSessionState state = AccountSessionState.signedIn,
  int generation = 4,
]) => AccountProjection(
  sessionState: state,
  operation: AccountOperation.none,
  generation: generation,
  profileFreshness: AccountProfileFreshness.unavailable,
  identity: const AccountIdentityProjection.unavailable(),
  compatibility: const AccountCompatibilityProjection.unavailable(),
  localeOptions: const [],
  timeZoneOptions: const [],
);

class Peer {
  Peer([this.subject = 'owner']) {
    final pair = InMemoryBridgeConnection.createPair();
    host = pair.host;
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 4)
      ..acceptHostCapabilities([
        'gameplayTime.export',
        'playerActivity.read',
        'playerActivity.save',
        'playerActivity.test',
      ]);
    subscription = host.incoming.listen((r) async {
      requests.add(r);
      if (r.name == 'bridge.cancel' || r.messageType != 'request') return;
      if ((r.name == 'account.getCurrent' && holdReads) ||
          (r.name == 'gameplayTime.export' && holdExports)) {
        held.add(r);
        return;
      }
      await reply(r);
    });
  }
  final String subject;
  late final BridgeConnection host;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  final held = <BridgeEnvelope>[];
  bool holdReads = false, holdExports = false;
  String exportOutcome = 'saved';
  Future<void> reply(BridgeEnvelope r) => host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: r.name,
      correlationId: r.correlationId,
      sessionGeneration: 4,
      accountContext: BridgeAccountContext(
        environment: 'test',
        authority: 'scm-fixture',
        subject: subject,
      ),
      status: 'ok',
      payload: switch (r.name) {
        'account.getCurrent' => {'schemaVersion': 1, 'state': 'signedIn'},
        'playerActivity.read' || 'playerActivity.save' => player.data(),
        'playerActivity.test' => {
          'schemaVersion': 1,
          'submitted': true,
          'reason': 'submitted',
        },
        _ => {'schemaVersion': 1, 'outcome': exportOutcome},
      },
    ),
  );
  int count(String name) => requests.where((r) => r.name == name).length;
  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await host.close();
  }
}

class ObservedPlayer extends PlayerActivityController {
  ObservedPlayer(super.request) : super(generation: () => 4);
  bool get subscribed => hasListeners;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite player panel replaces controller listener and read', (
      t,
    ) async {
      var aReads = 0, bReads = 0;
      final a = ObservedPlayer((n, p) async {
        aReads++;
        return player.data();
      });
      final b = ObservedPlayer((n, p) async {
        bReads++;
        return player.data()..['position'] = 2;
      });
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      var current = a;
      late StateSetter update;
      await mount(
        t,
        StatefulBuilder(
          builder: (_, s) {
            update = s;
            return PlayerActivityConnectedPanel(
              controller: current,
              showClose: false,
            );
          },
        ),
        suite,
      );
      expect(aReads, 1);
      update(() => current = b);
      await t.pump();
      await t.pumpAndSettle();
      expect(bReads, 1);
      expect(a.subscribed, false);
      expect(b.subscribed, true);
      await t.pumpWidget(const SizedBox());
    });
    for (final kind in ['player', 'export']) {
      testWidgets('$suite $kind factory preserves keyboard opening source', (
        t,
      ) async {
        final peer = Peer();
        final account = ValueNotifier(projection());
        addTearDown(peer.close);
        addTearDown(account.dispose);
        late BuildContext caller;
        await mount(
          t,
          Builder(
            builder: (context) {
              caller = context;
              return const Text('Open');
            },
          ),
          suite,
        );
        final pending = runStarBridgeActivation<void>(
          InteractionSource.keyboard,
          () => kind == 'player'
              ? showPlayerActivityDialog(caller, peer.session)
              : showGameplayDataExportDialog(caller, account, peer.session),
        );
        await t.pump();
        await t.pumpAndSettle();
        final target = find.byKey(
          Key(
            kind == 'player'
                ? 'settings-entry-player-activity'
                : 'settings-entry-local-data-management',
          ),
        );
        final context = t.element(target);
        final route = ModalRoute.of(context);
        Navigator.of(context).pop();
        await t.pumpAndSettle();
        await pending;
        expect(route, isA<StarBridgeDialogRoute>());
        expect((route as StarBridgeDialogRoute).instant, true);
        await t.pumpWidget(const SizedBox());
      });
    }
    for (final axis in ['account', 'session']) {
      testWidgets('$suite export dialog replaces $axis with same generation', (
        t,
      ) async {
        final a = Peer('old'), b = Peer('new');
        final first = ValueNotifier(projection()),
            second = ValueNotifier(projection());
        addTearDown(a.close);
        addTearDown(b.close);
        addTearDown(first.dispose);
        addTearDown(second.dispose);
        var account = first, session = a.session;
        late StateSetter update;
        await mount(
          t,
          StatefulBuilder(
            builder: (_, s) {
              update = s;
              return GameplayDataExportDialog(
                account: account,
                session: session,
              );
            },
          ),
          suite,
        );
        expect(a.count('account.getCurrent'), 1);
        update(() {
          if (axis == 'account') {
            account = second;
          } else {
            session = b.session;
          }
        });
        await t.pump();
        await t.pumpAndSettle();
        expect(
          axis == 'account'
              ? a.count('account.getCurrent')
              : b.count('account.getCurrent'),
          axis == 'account' ? 2 : 1,
        );
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
