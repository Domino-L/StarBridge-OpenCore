import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

final _target = 'a' * 32;
final _revision = 'b' * 64;
Map<String, Object?> shipRow() => {
  'shipRef': 'c' * 32,
  'code': 'fixture-ship',
  'displayName': 'Shared ship',
  'ownerMemberRef': 'd' * 32,
  'ownerGameName': '',
  'ownerCallsign': 'Pilot',
  'ownerOnline': true,
  'ownerLiveStatus': 'InGame',
  'ownerIsSelf': false,
  'ownerHasAvatar': true,
  'sharedAt': null,
  'hangarImportedAt': '2026-09-08T00:00:00Z',
  'roleCategory': 'Utility',
  'catalogSpec': '大型',
  'catalogRole': '运输',
  'catalogStatus': 'Flyable',
  'catalogPriceUsd': null,
  'hasCustomImage': true,
  'customImageCropFocusX': .3,
  'customImageCropFocusY': .7,
  'customImageCropZoom': 1.4,
};
Map<String, Object?> shipPage() => {
  'schemaVersion': 1,
  'targetRef': _target,
  'revision': _revision,
  'offset': 0,
  'next': null,
  'totalCount': 1,
  'ships': [shipRow()],
};

void main() {
  testWidgets(
    'full-library Host search has a finite budget beyond the default 15 seconds',
    (tester) async {
      final host = CommunityHarness(
        capabilities: ['communities.ships'],
        holdNames: {'communities.ships'},
        responses: {'communities.ships': shipPage()},
      );
      addTearDown(host.close);
      var completed = false;
      Object? error;
      final read = host.adapter
          .readShips(_target)
          .then(
            (_) {
              completed = true;
            },
            onError: (Object e) {
              error = e;
            },
          );
      await tester.pump();
      expect(
        host.requests.where((r) => r.name == 'communities.ships'),
        hasLength(1),
      );
      await tester.pump(const Duration(seconds: 31));
      expect(completed, isFalse);
      expect(error, isNull);
      await host.reply(
        host.requests.lastWhere((r) => r.name == 'communities.ships'),
      );
      await tester.pump();
      await read;
      expect(completed, isTrue);
      expect(error, isNull);
      error = null;
      final expired = host.adapter
          .readShips(_target)
          .then(
            (_) {},
            onError: (Object e) {
              error = e;
            },
          );
      await tester.pump();
      await tester.pump(const Duration(seconds: 46));
      await expired;
      expect(error, isA<CommunityFailure>());
    },
  );
  test(
    'library query searches all visible ships and preserves matched count',
    () async {
      final query = CommunityShipQuery(
        text: ' a&b ',
        sort: 'name',
        descending: false,
        culture: 'en-US',
      );
      final page = shipPage()
        ..['queryVersion'] = 2
        ..['query'] = query.toPayload()
        ..['totalCount'] = 501
        ..['matchedCount'] = 1;
      final host = CommunityHarness(
        capabilities: ['communities.ships'],
        responses: {'communities.ships': page},
      );
      addTearDown(host.close);
      final result = await host.adapter.readShips(_target, query: query);
      expect(result.totalCount, 501);
      expect(result.matchedCount, 1);
      expect(result.next, isNull);
      expect(result.query, query);
      expect(host.requests.last.payload['query'], query.toPayload());
      expect(query.text, 'a&b');
    },
  );
  test(
    'library query response cannot echo another filter or omit query version',
    () async {
      final query = CommunityShipQuery(filter: 'capital');
      for (final mode in ['echo', 'version', 'count']) {
        final page = shipPage()
          ..['queryVersion'] = 2
          ..['query'] = query.toPayload()
          ..['matchedCount'] = 1;
        if (mode == 'echo') {
          page['query'] = CommunityShipQuery(filter: 'small').toPayload();
        }
        if (mode == 'version') page['queryVersion'] = 0;
        if (mode == 'count') page['matchedCount'] = 2;
        final host = CommunityHarness(
          capabilities: ['communities.ships'],
          responses: {'communities.ships': page},
        );
        addTearDown(host.close);
        await expectLater(
          host.adapter.readShips(_target, query: query),
          throwsA(isA<CommunityFailure>()),
        );
      }
    },
  );
  test(
    'unsupported library service cannot fall back to a loaded-page filter',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.ships'],
        error: 'communities.upgradeRequired',
      );
      addTearDown(host.close);
      await expectLater(
        host.adapter.readShips(_target, query: CommunityShipQuery()),
        throwsA(
          isA<CommunityFailure>().having(
            (e) => e.code,
            'code',
            'upgradeRequired',
          ),
        ),
      );
      expect(
        host.requests.where((r) => r.name == 'communities.ships').length,
        1,
      );
    },
  );
  test('library query rejects unsupported controls and cultures', () {
    for (final create in [
      () => CommunityShipQuery(filter: 'private'),
      () => CommunityShipQuery(sort: 'raw-id'),
      () => CommunityShipQuery(culture: 'invalid'),
      () => CommunityShipQuery(text: 'a\nb'),
    ]) {
      expect(create, throwsFormatException);
    }
  });
  test(
    'production ships adapter carries current account and bounded request',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.ships'],
        responses: {'communities.ships': shipPage()},
      );
      addTearDown(host.close);
      expect(host.adapter.shipsAvailable, isTrue);
      final page = await host.adapter.readShips(_target);
      expect(host.requests.map((r) => r.name), [
        'account.getCurrent',
        'communities.ships',
      ]);
      expect(host.requests.last.accountContext?.subject, 'test-subject');
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'targetRef': _target,
        'offset': 0,
        'revision': null,
      });
      expect(page.ships.single.ownerGameName, isEmpty);
      expect(page.ships.single.sharedAt, isNull);
      expect(page.ships.single.catalogPriceUsd, isNull);
      expect(page.ships.single.customImageCropFocusX, .3);
      expect(page.ships.single.hangarImportedAt, DateTime.utc(2026, 9, 8));
    },
  );
  test(
    'missing ships capability does not send account or legacy bulk requests',
    () async {
      final host = CommunityHarness(capabilities: []);
      addTearDown(host.close);
      expect(host.adapter.shipsAvailable, isFalse);
      await expectLater(
        host.adapter.readShips(_target),
        throwsA(isA<CommunityFailure>()),
      );
      expect(host.requests, isEmpty);
    },
  );
  test(
    'invalid cursor or raw code is rejected before Bridge requests',
    () async {
      final host = CommunityHarness(capabilities: ['communities.ships']);
      addTearDown(host.close);
      for (final run in [
        () => host.adapter.readShips('raw-organization-code'),
        () => host.adapter.readShips(_target, offset: 1),
        () => host.adapter.readShips(_target, offset: 20),
        () => host.adapter.readShips(_target, revision: 'bad'),
      ]) {
        await expectLater(run(), throwsA(isA<CommunityFailure>()));
      }
      expect(host.requests, isEmpty);
    },
  );
  test('same model instances remain distinct and list is immutable', () {
    final page = shipPage()..['totalCount'] = 2;
    page['ships'] = [shipRow(), shipRow()..['shipRef'] = 'e' * 32];
    final parsed = CommunityShipsPage.parse(page);
    expect(parsed.ships.length, 2);
    expect(() => parsed.ships.clear(), throwsUnsupportedError);
  });
  for (final kind in [
    'schema',
    'revision',
    'count',
    'next',
    'offset',
    'ref',
    'duplicate',
    'time',
    'crop',
    'flag',
    'large',
    'control',
  ]) {
    test('reject malformed ship page: $kind', () {
      final root = shipPage();
      final row = (root['ships'] as List).single as Map<String, Object?>;
      switch (kind) {
        case 'schema':
          root['schemaVersion'] = 2;
        case 'revision':
          root['revision'] = 'bad';
        case 'count':
          root['totalCount'] = 2;
        case 'next':
          root['next'] = 20;
        case 'offset':
          root['offset'] = 1;
        case 'ref':
          row['ownerMemberRef'] = 'account:raw-id';
        case 'duplicate':
          root['totalCount'] = 2;
          root['ships'] = [row, Map<String, Object?>.from(row)];
        case 'time':
          row['sharedAt'] = 'unknown';
        case 'crop':
          row['customImageCropFocusY'] = 1.1;
        case 'flag':
          row['ownerOnline'] = 'true';
        case 'large':
          row['displayName'] = 'x' * 513;
        case 'control':
          row['ownerCallsign'] = 'Pilot\n';
      }
      expect(() => CommunityShipsPage.parse(root), throwsFormatException);
    });
  }
  test('continuation must echo requested target offset and revision', () async {
    for (final kind in ['target', 'offset', 'revision']) {
      final page = shipPage()
        ..['offset'] = 20
        ..['totalCount'] = 21;
      if (kind == 'target') page['targetRef'] = 'f' * 32;
      if (kind == 'offset') {
        page['offset'] = 0;
        page['totalCount'] = 1;
      }
      if (kind == 'revision') page['revision'] = 'f' * 64;
      final host = CommunityHarness(
        capabilities: ['communities.ships'],
        responses: {'communities.ships': page},
      );
      addTearDown(host.close);
      await expectLater(
        host.adapter.readShips(_target, offset: 20, revision: _revision),
        throwsA(isA<CommunityFailure>()),
      );
    }
  });
  test('server conflict surfaces without retry or fallback', () async {
    final host = CommunityHarness(
      capabilities: ['communities.ships'],
      error: 'communities.shipsChanged',
    );
    addTearDown(host.close);
    await expectLater(
      host.adapter.readShips(_target),
      throwsA(
        isA<CommunityFailure>().having((e) => e.code, 'code', 'shipsChanged'),
      ),
    );
    expect(host.requests.where((r) => r.name == 'communities.ships').length, 1);
  });
  test(
    'account change cancels a pending ships read and discards late response',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.ships'],
        holdNames: {'communities.ships'},
        responses: {'communities.ships': shipPage()},
      );
      addTearDown(host.close);
      final rejected = expectLater(
        host.adapter.readShips(_target),
        throwsA(isA<CommunityFailure>()),
      );
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
      await rejected;
      await host.reply(
        host.requests.firstWhere((r) => r.name == 'communities.ships'),
      );
      expect(host.session.activeGeneration, 5);
    },
  );
}
