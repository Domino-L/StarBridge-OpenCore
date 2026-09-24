import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_creation_port.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

// Deliberately small wire fixture; the complete WPF catalog is asserted in Core/Host.
Map<String, Object?> optionsPayload() => {
  'schemaVersion': 1,
  'maxTags': 5,
  'categories': [
    {
      'id': 'exploration',
      'name': '探索',
      'accentHex': '#55AACC',
      'description': '探索活动',
    },
  ],
  'tags': [
    {
      'id': 'scouting',
      'name': '侦察',
      'categoryId': 'exploration',
      'description': '侦察航线',
    },
  ],
  'timeZones': [
    {'id': 'UTC', 'name': 'UTC'},
  ],
  'defaultTimeZoneId': 'UTC',
  'defaultActiveFrom': '19:00',
  'defaultActiveTo': '22:00',
  'defaultSystem': 'stanton',
};

Map<String, Object?> createdCard({String relationship = 'owner'}) => {
  'targetRef': 'a' * 32,
  'name': 'Test Organization',
  'description': '',
  'language': 'zh-CN',
  'activeTime': '19:00–22:00',
  'relationship': relationship,
  'joinMode': 'direct',
  'actions': [],
};

void main() {
  test(
    'Host preflight validation preserves an editable rejected draft',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.create'],
        error: 'communities.dataInvalid',
      );
      addTearDown(host.close);
      final outcome = await host.adapter.createCommunity('b' * 32, {});
      expect(outcome.status, 'rejected');
      expect(outcome.error, 'invalidDraft');
      expect(
        host.requests.where((r) => r.name == 'communities.create'),
        hasLength(1),
      );
    },
  );

  test(
    'Native image wire carries a reference and crop coordinates, never a path',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.logo'],
        responses: {
          'communities.pickLogo': {
            'schemaVersion': 1,
            'status': 'selected',
            'source': {
              'sourceRef': 'a' * 32,
              'previewImageData': 'data:image/png;base64,AQ==',
              'width': 512,
              'height': 256,
            },
          },
          'communities.cropLogo': {
            'schemaVersion': 1,
            'status': 'cropped',
            'imageData': 'data:image/png;base64,AQ==',
          },
          'communities.clearLogo': {'schemaVersion': 1, 'status': 'cleared'},
        },
      );
      addTearDown(host.close);
      expect(host.adapter.canPickLogo, isTrue);
      final source = await host.adapter.pickLogo();
      expect(source!.width, 512);
      await host.adapter.cropLogo(source.sourceRef, .25, 0, 1);
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'sourceRef': 'a' * 32,
        'x': .25,
        'y': 0.0,
        'size': 1.0,
      });
      await host.adapter.clearLogo();
      expect(host.requests.last.payload, {'schemaVersion': 1});
    },
  );
  test(
    'Creation options require the independent creation capability',
    () async {
      final host = CommunityHarness();
      addTearDown(host.close);
      await expectLater(
        host.adapter.creationOptions(),
        throwsA(isA<CommunityFailure>()),
      );
      expect(host.requests, isEmpty);
    },
  );

  test(
    'Options carry current identity and preserve the catalog values',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.create'],
        responses: {'communities.creationOptions': optionsPayload()},
      );
      addTearDown(host.close);
      final options = await host.adapter.creationOptions();
      expect(options.tags.single.id, 'scouting');
      expect(options.defaultTimeZoneId, 'UTC');
      expect(host.requests.last.accountContext?.subject, 'test-subject');
      expect(host.requests.last.payload, {'schemaVersion': 1});
      expect(() => options.tags.clear(), throwsUnsupportedError);
    },
  );

  test('Creation sends the same explicit intent and only accepts owner confirmation', () async {
    final host = CommunityHarness(
      capabilities: ['communities.create'],
      responses: {
        'communities.create': {
          'schemaVersion': 1,
          'status': 'accepted',
          'organization': createdCard(),
        },
      },
    );
    addTearDown(host.close);
    final draft = <String, Object?>{
      'schemaVersion': 1,
      'name': 'Test Organization',
    };
    final outcome = await host.adapter.createCommunity('b' * 32, draft);
    expect(outcome.status, 'accepted');
    expect(outcome.organization?.relationship, 'owner');
    expect(host.requests.last.payload, {
      'schemaVersion': 1,
      'requestId': 'b' * 32,
      'draft': draft,
    });
    expect(
      host.requests.where((r) => r.name == 'communities.create'),
      hasLength(1),
    );
  });

  for (final response in [
    {
      'schemaVersion': 1,
      'status': 'accepted',
      'organization': createdCard(relationship: 'member'),
    },
    {'schemaVersion': 1, 'status': 'accepted'},
    {'schemaVersion': 2, 'status': 'accepted', 'organization': createdCard()},
    {'schemaVersion': 1, 'status': 'unexpected'},
  ]) {
    test(
      'Malformed or non-owner acknowledgment is uncertain: $response',
      () async {
        final host = CommunityHarness(
          capabilities: ['communities.create'],
          responses: {'communities.create': response},
        );
        addTearDown(host.close);
        final outcome = await host.adapter.createCommunity('b' * 32, {});
        expect(outcome.status, 'unknown');
        expect(outcome.organization, isNull);
        expect(
          host.requests.where((r) => r.name == 'communities.create'),
          hasLength(1),
        );
      },
    );
  }

  test('Server rejection is not transformed into success or retried', () async {
    final host = CommunityHarness(
      capabilities: ['communities.create'],
      responses: {
        'communities.create': {
          'schemaVersion': 1,
          'status': 'rejected',
          'error': 'codeUnavailable',
        },
      },
    );
    addTearDown(host.close);
    final result = await host.adapter.createCommunity('b' * 32, {});
    expect(result.status, 'rejected');
    expect(result.error, 'codeUnavailable');
    expect(
      host.requests.where((r) => r.name == 'communities.create'),
      hasLength(1),
    );
  });

  test(
    'Options refuse unknown categories, duplicate IDs and invalid defaults',
    () {
      for (final mutation in <void Function(Map<String, Object?>)>[
        (p) => p['maxTags'] = 6,
        (p) => p['defaultTimeZoneId'] = 'unknown',
        (p) => p['defaultSystem'] = 'unknown',
        (p) => p['defaultActiveFrom'] = '25:99',
        (p) => (p['categories'] as List).add((p['categories'] as List).first),
        (p) => ((p['tags'] as List).first as Map)['categoryId'] = 'missing',
        (p) => ((p['categories'] as List).first as Map)['accentHex'] = 'red',
      ]) {
        final payload = optionsPayload();
        mutation(payload);
        expect(
          () => CommunityCreationOptions.parse(payload),
          throwsFormatException,
        );
      }
    },
  );
}
