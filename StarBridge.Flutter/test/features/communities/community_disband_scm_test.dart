// Plan item 13 follow-up: a migrated owner disbands with SCM re-confirmation.
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_disband_controller.dart';
import 'package:starbridge_flutter/features/communities/community_disband_port.dart';

import 'bridge_communities_test.dart' show CommunityHarness;
import 'community_disband_test.dart' show DisbandFake, disbandPayload;

void main() {
  test('the preview accepts SCM re-confirmation and nothing else new', () {
    final scm = CommunityDisbandPreview.parse({
      ...disbandPayload(),
      'credentialMode': 'scmRevalidation',
    });
    expect(scm.scmRevalidation, isTrue);
    expect(
      CommunityDisbandPreview.parse(disbandPayload()).scmRevalidation,
      isFalse,
    );
    expect(
      () => CommunityDisbandPreview.parse({
        ...disbandPayload(),
        'credentialMode': 'scmPassword',
      }),
      throwsFormatException,
    );
  });

  test('SCM re-confirmation confirms without a password', () async {
    final port = DisbandFake()
      ..preview = CommunityDisbandPreview.parse({
        ...disbandPayload(),
        'credentialMode': 'scmRevalidation',
      });
    final model = CommunityDisbandController(port, 'a' * 32);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    await model.load();
    await model.confirm('');
    expect(port.writes, 1);
    expect(port.sentPassword, '');
  });

  test('an old-account owner still needs the password', () async {
    final port = DisbandFake();
    final model = CommunityDisbandController(port, 'a' * 32);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    await model.load();
    await model.confirm('');
    expect(port.writes, 0);
  });

  test(
    'the bridge passes an empty password through for the Host to check',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.disbandPreview', 'communities.disband'],
        responses: {
          'communities.disband': {'schemaVersion': 1, 'status': 'accepted'},
          'communities.disbandPreview': {
            ...disbandPayload(),
            'credentialMode': 'scmRevalidation',
          },
        },
      );
      addTearDown(host.close);
      final early = await host.adapter.disband('a' * 32, 'b' * 32, '');
      expect(
        early.error,
        'passwordInvalid',
        reason: 'no password only after an SCM re-confirmation preview',
      );
      final preview = await host.adapter.readDisband('a' * 32);
      expect(preview.scmRevalidation, isTrue);
      final outcome = await host.adapter.disband('a' * 32, 'b' * 32, '');
      expect(outcome.status, 'accepted');
      final sent = host.requests.lastWhere(
        (r) => r.name == 'communities.disband',
      );
      expect(sent.payload['password'], '');
      final withPassword = await host.adapter.disband('a' * 32, 'b' * 32, 'x');
      expect(withPassword.error, 'passwordInvalid');
    },
  );
}
