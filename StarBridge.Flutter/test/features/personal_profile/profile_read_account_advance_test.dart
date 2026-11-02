
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/hangar/bridge_local_hangar.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_local_personal_profile.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_read_admission.dart';
import 'package:starbridge_flutter/features/personal_profile/profile_read_scope.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

const proof = AccountDisplayHandoff(
  displayKey: '0123456789abcdef0123456789abcdef',
  sourceGeneration: 0,
  route: AccountRoute(
    environment: 'integration',
    authority: 'synthetic',
    subject: 'advance-observer',
  ),
);
BridgeEnvelope event({
  String name = 'account.changed',
  int generation = 1,
  int? sequence = 1,
  Object schema = 1,
  String type = 'event',
}) => BridgeEnvelope(
  protocolVersion: 1,
  messageType: type,
  name: name,
  sessionGeneration: generation,
  sequence: sequence,
  payload: {'schemaVersion': schema},
);
void main() {
  test(
    'account advance observation contains only the exact next-generation cause',
    () {
      final actual = ProfileReadAccountAdvance.observe(event(), 0, 1)!;
      expect(actual.sourceGeneration, 0);
      expect(actual.generation, 1);
      expect(actual.matches(proof), isTrue);
      expect(const ProfileReadAccountAdvance(1, 2).matches(proof), isFalse);
      for (final raw in [
        event(name: 'bootstrap.invalidated'),
        event(name: 'onboarding.changed'),
        event(generation: 0),
        event(generation: 2),
        event(schema: 1.0),
        event(schema: 2),
        event(sequence: null),
        event(sequence: -1),
        event(type: 'response'),
      ]) {
        expect(ProfileReadAccountAdvance.observe(raw, 0, 1), isNull);
      }
      expect(ProfileReadAccountAdvance.observe(event(), 0, 2), isNull);
      expect(ProfileReadAccountAdvance.observe(event(), 1, 1), isNull);
      expect(
        ProfileReadAccountAdvance.observe(event(generation: 0), -1, 0),
        isNull,
      );
    },
  );
  for (final local in [false, true]) {
    test(
      'production ${local ? 'local composed' : 'remote'} port preserves hard invalidation boundaries',
      () async {
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 0,
        );
        final remote = BridgePersonalProfileAdapter(session);
        final module = createPersonalProfileModule(
          local
              ? BridgeLocalPersonalProfile(
                  session,
                  remote: remote,
                  hangar: () => BridgeLocalHangar(session),
                )
              : remote,
        );
        final requests = <BridgeEnvelope>[];
        final subscription = pair.host.incoming.listen(requests.add);
        (module as PersonalProfileReadAdmission).registerReadAdmission(
          () => false,
        );
        addTearDown(() async {
          module.dispose();
          await Future<void>.delayed(Duration.zero);
          await session.close();
          await subscription.cancel();
          await pair.host.close();
        });
        await module.initialize();
        Future<ProfileReadObservation> publish(BridgeEnvelope raw) async {
          await pair.host.send(raw);
          for (var i = 0; i < 6; i++) {
            await Future<void>.delayed(Duration.zero);
          }
          final observed =
              (module as ProfileReadObservationOwner).readObservation!;
          expect(observed.phase, ProfileReadPhase.invalidated);
          expect(
            requests,
            isEmpty,
            reason: 'A cause observation never bypasses read admission.',
          );
          return observed;
        }

        expect((await publish(event())).accountAdvance?.matches(proof), isTrue);
        expect(
          (await publish(event(sequence: 2))).accountAdvance,
          isNull,
          reason: 'Duplicate generation is a hard invalidation.',
        );
        expect(
          (await publish(event(name: 'bootstrap.invalidated', sequence: 3)))
              .accountAdvance,
          isNull,
        );
        expect(
          (await publish(event(generation: 3, sequence: 4))).accountAdvance,
          isNull,
        );
        final next = (await publish(event(generation: 4, sequence: 5)))
            .accountAdvance;
        expect(next?.sourceGeneration, 3);
        expect(next?.generation, 4);
        expect(next?.matches(proof), isFalse);
        expect(
          (await publish(event(generation: 5, sequence: 6, schema: 1.0)))
              .accountAdvance,
          isNull,
        );
      },
    );
  }
}
