import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_connection_mode_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_controller.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_display_session.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/profile_read_scope.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'profile_handoff_failure_test.dart' show ProfileLifetimeFixture;

// The mode adapter/controller and display owner are production. Profile data
// scheduling remains the explicit synthetic scoped port from the prior tests.
void main() {
  for (final legacy in [false, true]) {
    test(
      'unsupported mode keeps original fresh profile admission, legacy=$legacy',
      () async {
        final f = ProfileLifetimeFixture();
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 8,
        )..acceptHostCapabilities(const ['personalProfile.getSelf']);
        final requests = <BridgeEnvelope>[];
        final subscription = pair.host.incoming.listen(requests.add);
        final mode = ConnectionModeController(
          BridgeConnectionModeAdapter(session),
        );
        PersonalProfileDisplaySession? display;
        try {
          await mode.refresh();
          expect(mode.snapshot.state, ConnectionModeState.unsupported);
          expect(mode.snapshot.scope, isNot(8));
          expect(mode.failed, isFalse);
          expect(mode.allowsOnlineTraffic, isTrue);
          f.account.value = AccountProjection(
            generation: 8,
            sessionState: legacy
                ? AccountSessionState.legacySignedIn
                : AccountSessionState.signedIn,
            operation: AccountOperation.none,
            profileFreshness: AccountProfileFreshness.cached,
            identity: const AccountIdentityProjection.unavailable(),
            compatibility: const AccountCompatibilityProjection.unavailable(),
            localeOptions: const [],
            timeZoneOptions: const [],
          );
          f.port.pending!.complete(await f.port.fresh());
          await f.online.initialize();
          expect(
            f.online.projection.value.availability,
            PersonalProfileAvailability.available,
          );
          expect((f.online as ProfileReadScopeOwner).readScope?.generation, 8);
          display = PersonalProfileDisplaySession(
            mode: mode,
            account: f.account,
            onlineModule: f.online,
            createPort: () =>
                throw StateError('No offline or substitute reader'),
          )..activate();
          expect(
            display.onlineDisplay,
            isTrue,
            reason: 'A supported absence of mode ownership must not hide the original scoped module.',
          );
          expect(display.displayModule, isNull);
          expect(display.permitsEditing, isTrue);
          expect(f.port.reads, 1);
          expect(
            requests,
            isEmpty,
            reason: 'Unsupported mode must not invent a mode RPC.',
          );
          f.port.pending = Completer<PersonalProfileSnapshot>();
          final reading = f.online.refresh();
          await Future<void>.delayed(Duration.zero);
          expect(
            f.port.reads,
            2,
            reason: 'The original reader remains admitted.',
          );
          f.port.pending!.complete(await f.port.fresh());
          await reading;
          expect(display.onlineDisplay, isTrue);
          expect(f.port.reads, 2);
          expect(f.port.saves, 0);
        } finally {
          display?.dispose();
          f.online.dispose();
          f.account.dispose();
          f.mode.dispose();
          mode.dispose();
          await subscription.cancel();
          await session.close();
          await pair.host.close();
        }
      },
    );
  }
  for (final pendingMode in [false, true]) {
    test(
      'unsupported policy preserves receipt and pending-owner guards: pendingMode=$pendingMode',
      () async {
        final f = ProfileLifetimeFixture();
        final pair = InMemoryBridgeConnection.createPair();
        final session =
            BridgeClientSession(connection: pair.client, sessionGeneration: 8)
              ..acceptHostCapabilities(
                pendingMode
                    ? const [BridgeConnectionModeAdapter.capability]
                    : const [],
              );
        final mode = ConnectionModeController(
          BridgeConnectionModeAdapter(session),
        );
        PersonalProfileDisplaySession? display;
        try {
          if (!pendingMode) await mode.refresh();
          expect(mode.snapshot.state, ConnectionModeState.unsupported);
          expect(mode.allowsOnlineTraffic, !pendingMode);
          f.account.value = const AccountProjection(
            generation: 8,
            sessionState: AccountSessionState.signedIn,
            operation: AccountOperation.none,
            profileFreshness: AccountProfileFreshness.cached,
            identity: AccountIdentityProjection.unavailable(),
            compatibility: AccountCompatibilityProjection.unavailable(),
            localeOptions: [],
            timeZoneOptions: [],
          );
          if (!pendingMode) {
            f.port.nextScope = ProfileReadScope(9, f.port.nextScope.route);
          }
          f.port.pending!.complete(await f.port.fresh());
          await f.online.initialize();
          expect(
            f.online.projection.value.availability,
            PersonalProfileAvailability.available,
          );
          display = PersonalProfileDisplaySession(
            mode: mode,
            account: f.account,
            onlineModule: f.online,
            createPort: () => throw StateError('No substitute reader'),
          )..activate();
          expect(display.onlineDisplay, isFalse);
          expect(display.permitsEditing, isFalse);
          expect(f.port.saves, 0);
          if (pendingMode) {
            await f.online.refresh();
            expect(
              f.port.reads,
              1,
              reason:
                  'An owned but unobserved mode still blocks original reads.',
            );
          }
        } finally {
          display?.dispose();
          f.online.dispose();
          f.account.dispose();
          f.mode.dispose();
          mode.dispose();
          await session.close();
          await pair.host.close();
        }
      },
    );
  }
}
