import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_chat_send_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

void main() {
  test('Host and WPF PascalCase preset package can be shared unchanged', () {
    const package =
        '{"Version":1,"Name":"Fixture","Settings":"1,0,1,1,1","Layout":"Notice,0,0,400,60"}';
    final value = CommunityChatSendIntent(
      targetRef: 'a' * 32,
      requestId: 'b' * 32,
      text: '',
      attachment: {
        'kind': 'overlay_preset',
        'title': 'Fixture',
        'summary': 'Fixture',
        'overlayPresetPackage': package,
      },
    );
    expect(value.attachment!['overlayPresetPackage'], package);
  });
  final attachment = <String, Object?>{
    'kind': 'overlay_preset',
    'title': 'Fixture',
    'summary': 'Shared fixture',
    'overlayPresetPackage': jsonEncode({
      'version': 1,
      'name': 'Fixture',
      'settings': '{}',
      'layout': '{}',
    }),
  };
  CommunityChatSendIntent intent({
    String text = 'hello\nworld',
    Map<String, Object?>? card,
  }) => CommunityChatSendIntent(
    targetRef: 'a' * 32,
    requestId: 'b' * 32,
    text: text,
    attachment: card,
  );
  Map<String, Object?> receipt() => {
    'schemaVersion': 1,
    'targetRef': 'a' * 32,
    'requestId': 'b' * 32,
    'status': 'accepted',
    'error': null,
    'sequence': 12,
  };
  test(
    'scoped send carries original multiline text and fixed request id once',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.sendChat'],
        responses: {'communities.sendChat': receipt()},
      );
      addTearDown(host.close);
      final value = intent(card: attachment);
      final result = await host.adapter.sendChat(value);
      expect(result.status, 'accepted');
      expect(result.sequence, 12);
      expect(host.requests.last.accountContext?.subject, 'test-subject');
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        ...value.toPayload(),
      });
      expect(
        host.requests.where((v) => v.name == 'communities.sendChat'),
        hasLength(1),
      );
    },
  );
  test(
    'missing send capability cannot use generic community commands',
    () async {
      final host = CommunityHarness();
      addTearDown(host.close);
      expect((await host.adapter.sendChat(intent())).status, 'rejected');
      expect(host.requests, isEmpty);
    },
  );
  test('attachment-only send is immutable and preserves exported package', () {
    final copy = Map<String, Object?>.from(attachment);
    final value = intent(text: '', card: copy);
    copy['title'] = 'changed';
    expect(value.attachment!['title'], 'Fixture');
    expect(
      value.attachment!['overlayPresetPackage'],
      attachment['overlayPresetPackage'],
    );
    expect(
      () => value.attachment!['title'] = 'changed',
      throwsUnsupportedError,
    );
  });
  test(
    'invalid length control characters and unsupported attachments rejected',
    () {
      for (final text in ['', 'x' * 1001, 'a\u0000b']) {
        expect(() => intent(text: text), throwsFormatException);
      }
      for (final (key, value) in <(String, Object?)>[
        ('kind', 'fleet_invitation'),
        ('title', 'x' * 65),
        ('summary', 'x' * 241),
        ('overlayPresetPackage', '{}'),
        ('extra', 'not allowed'),
      ]) {
        expect(
          () => intent(
            card: Map<String, Object?>.from(attachment)..[key] = value,
          ),
          throwsFormatException,
        );
      }
    },
  );
  for (final (key, value) in <(String, Object?)>[
    ('schemaVersion', 2),
    ('targetRef', 'c' * 32),
    ('requestId', 'c' * 32),
    ('status', 'sent'),
    ('sequence', 0),
    ('sequence', null),
    ('error', 'failure'),
  ]) {
    test('malformed send receipt $key never clears draft', () async {
      final host = CommunityHarness(
        capabilities: ['communities.sendChat'],
        responses: {'communities.sendChat': receipt()..[key] = value},
      );
      addTearDown(host.close);
      final result = await host.adapter.sendChat(intent());
      expect(result.status, 'unknown');
      expect(result.sequence, isNull);
      expect(
        host.requests.where((v) => v.name == 'communities.sendChat'),
        hasLength(1),
      );
    });
  }
  test('account change leaves late send response uncertain', () async {
    final host = CommunityHarness(
      capabilities: ['communities.sendChat'],
      holdNames: {'communities.sendChat'},
      responses: {'communities.sendChat': receipt()},
    );
    addTearDown(host.close);
    final pending = host.adapter.sendChat(intent());
    await host.readArrived.future;
    final invalidated = host.adapter.invalidations.first;
    await host.connection.send(
      const BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'account.changed',
        sessionGeneration: 5,
        sequence: 1,
        payload: {'schemaVersion': 1},
      ),
    );
    await invalidated;
    expect((await pending).status, 'unknown');
    await host.reply(
      host.requests.firstWhere((v) => v.name == 'communities.sendChat'),
    );
    expect(host.session.activeGeneration, 5);
  });
}
