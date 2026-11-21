// SCM greenlight (user 11-15): once the relay offers the account migration,
// SCM-only accounts use the relay account features and may disband; nothing is
// hidden behind "link an old account first" any more.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/account_scm_only.dart';
import 'package:starbridge_flutter/features/account/account_migration_controller.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/account_relay_features.dart';
import 'package:starbridge_flutter/features/communities/bridge_communities.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'account_migration_test.dart' show FakeMigration, account, reading;

void main() {
  const unlinked = AccountCompatibilityIdentityState.unlinked;

  test('SCM-only is blocked only while the migration is not offered', () async {
    final projection = ValueNotifier(account(identity: unlinked));
    expect(
      relayAccountFeaturesBlocked(projection),
      isTrue,
      reason: 'No shared migration status: the switch reads as off.',
    );
    final port = FakeMigration()
      ..next = reading(available: false, state: 'none', resultPending: false);
    final controller = AccountMigrationController(
      port,
      projection,
      pollFor: Duration.zero,
    )..shareThrough(projection);
    final flag = AccountScmOnly(projection);
    var changes = 0;
    flag.addListener(() => changes++);
    await pumpEventQueue();
    expect(relayAccountFeaturesBlocked(projection), isTrue);
    expect(flag.value, isTrue);

    port.next = reading(state: 'none', resultPending: false);
    await controller.load(refresh: true);
    await pumpEventQueue();
    expect(controller.value.offered, isTrue);
    expect(
      relayAccountFeaturesBlocked(projection),
      isFalse,
      reason: 'The relay serves SCM-only accounts once migration is offered.',
    );
    expect(flag.value, isFalse);
    expect(changes, 1);

    flag.dispose();
    controller.dispose();
  });

  test('offer changes reach listeners that subscribed before the controller '
      'was shared, and disposal blocks again', () async {
    final projection = ValueNotifier(account(identity: unlinked));
    var pings = 0;
    AccountMigrationController.offerChangesFor(projection)
        .addListener(() => pings++);
    final port = FakeMigration()
      ..next = reading(state: 'none', resultPending: false);
    final controller = AccountMigrationController(
      port,
      projection,
      pollFor: Duration.zero,
    )..shareThrough(projection);
    await pumpEventQueue();
    expect(controller.value.offered, isTrue);
    expect(pings, greaterThanOrEqualTo(1));
    expect(relayAccountFeaturesBlocked(projection), isFalse);
    final before = pings;
    controller.dispose();
    expect(pings, before + 1, reason: 'Disposal tells listeners to re-read.');
    expect(relayAccountFeaturesBlocked(projection), isTrue);
  });

  test('linked, unknown and signed-out accounts are never blocked', () {
    for (final identity in AccountCompatibilityIdentityState.values) {
      if (identity == unlinked) continue;
      expect(
        relayAccountFeaturesBlocked(ValueNotifier(account(identity: identity))),
        isFalse,
        reason: '$identity',
      );
    }
    expect(
      relayAccountFeaturesBlocked(
        ValueNotifier(const AccountProjection.loading()),
      ),
      isFalse,
    );
  });

  for (final blocked in [true, false]) {
    test('invitation delivery is offered; disband follows the relay '
        '(blocked=$blocked)', () async {
      final pair = InMemoryBridgeConnection.createPair();
      final session =
          BridgeClientSession(connection: pair.client, sessionGeneration: 1)
            ..acceptHostCapabilities([
              'communities.read',
              'communities.disbandPreview',
              'communities.disband',
              'communities.sendInvite',
            ]);
      final adapter = BridgeCommunities(session, scmOnly: () => blocked);
      expect(adapter.disbandAvailable, !blocked);
      expect(adapter.invitationSendingAvailable, isTrue);
      await adapter.close();
      await session.close();
      await pair.host.close();
    });
  }
}
