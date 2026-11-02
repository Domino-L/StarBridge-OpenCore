import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/social_activity.dart';
import 'package:starbridge_flutter/features/direct_messages/direct_messages_contract.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_direct_messages_test.dart' as wire;

class PushHarness extends wire.Harness {
  final waits = <BridgeEnvelope>[];
  @override
  Future<void> reply(BridgeEnvelope request) {
    if (request.name != 'social.wait') return super.reply(request);
    waits.add(request);
    return Future.value();
  }

  Future<void> answer(Object? healthy, int version, {bool invalid = false}) =>
      connection.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: 'social.wait',
          correlationId: waits.last.correlationId,
          sessionGeneration: waits.last.sessionGeneration,
          accountContext: waits.last.accountContext,
          status: 'ok',
          payload: {
            'schemaVersion': 1,
            'instance': invalid ? 'invalid' : 'a' * 32,
            'version': version,
            'directMessagesPushHealthy': ?healthy,
          },
        ),
      );
}

void main() {
  testWidgets(
    'DM push health distinguishes legacy waits, push, HTTP fallback and failed waits',
    (tester) async {
      final harness = PushHarness();
      harness.session.acceptHostCapabilities([
        'social.wait',
        'directMessages.read',
      ]);
      final source = SocialActivity(harness.session);
      addTearDown(() async {
        source.dispose();
        await harness.close();
      });
      await tester.pump(const Duration(milliseconds: 1));
      await harness.answer(null, 0);
      await tester.pump();
      expect(harness.adapter.activityHealthy, isTrue);
      expect(harness.adapter.pushHealthy, isFalse);
      expect(directMessageReceptionHealthy(harness.adapter), isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      await harness.answer(true, 1);
      await tester.pump();
      expect(harness.adapter.pushHealthy, isTrue);
      expect(directMessageReceptionHealthy(harness.adapter), isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      await harness.answer(false, 1);
      await tester.pump();
      expect(harness.adapter.activityHealthy, isTrue);
      expect(harness.adapter.pushHealthy, isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      await harness.answer(true, 2);
      await tester.pump();
      expect(harness.adapter.pushHealthy, isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      await harness.answer(true, 3, invalid: true);
      await tester.pump();
      expect(harness.adapter.pushHealthy, isFalse);
      source.dispose();
      await tester.pump();
    },
  );
}
