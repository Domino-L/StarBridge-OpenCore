import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_disband_controller.dart';
import 'package:starbridge_flutter/features/communities/community_disband_port.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

Map<String, Object?> disbandPayload() => {
  'schemaVersion': 1,
  'targetRef': 'a' * 32,
  'confirmationRef': 'b' * 32,
  'name': '示例组织',
  'memberCount': 48,
  'canDisband': true,
  'credentialMode': 'legacyPassword',
};

class DisbandFake implements CommunityDisbandPort {
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  bool disbandAvailable = true;
  int reads = 0, writes = 0;
  String? sentPassword;
  CommunityDisbandPreview preview = CommunityDisbandPreview.parse(
    disbandPayload(),
  );
  CommunityDisbandOutcome outcome = const CommunityDisbandOutcome('accepted');
  Completer<CommunityDisbandPreview>? reading;
  Completer<CommunityDisbandOutcome>? writing;
  @override
  Future<CommunityDisbandPreview> readDisband(String targetRef) async {
    reads++;
    return reading?.future ?? preview;
  }

  @override
  Future<CommunityDisbandOutcome> disband(
    String targetRef,
    String confirmationRef,
    String password,
  ) async {
    writes++;
    sentPassword = password;
    return writing?.future ?? outcome;
  }
}

void main() {
  test(
    'dedicated capabilities and exact account scoped disband payload',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.disbandPreview', 'communities.disband'],
        responses: {
          'communities.disbandPreview': disbandPayload()..['isExample'] = true,
          'communities.disband': {'schemaVersion': 1, 'status': 'accepted'},
        },
      );
      addTearDown(host.close);
      expect(host.adapter.disbandAvailable, isTrue);
      final preview = await host.adapter.readDisband('a' * 32);
      expect(
        preview.isExample,
        isFalse,
      ); // Host data cannot bypass the password UI.
      expect(
        (await host.adapter.disband(
          preview.targetRef,
          preview.confirmationRef,
          ' fixture-password ',
        )).status,
        'accepted',
      );
      expect(host.requests.last.payload, {
        'schemaVersion': 1,
        'targetRef': 'a' * 32,
        'confirmationRef': 'b' * 32,
        'password': ' fixture-password ',
      });
      expect(host.requests.last.accountContext?.subject, 'test-subject');
    },
  );
  for (final capabilities in [
    <String>['communities.commands'],
    ['communities.disbandPreview'],
    ['communities.disband'],
  ]) {
    test('incomplete capabilities never write $capabilities', () async {
      final host = CommunityHarness(capabilities: capabilities);
      addTearDown(host.close);
      expect(host.adapter.disbandAvailable, isFalse);
      expect(
        (await host.adapter.disband('a' * 32, 'b' * 32, 'fixture')).error,
        'unavailable',
      );
      expect(host.requests, isEmpty);
    });
  }
  for (final (key, value) in <(String, Object?)>[
    ('schemaVersion', 2),
    ('credentialMode', 'scmPassword'),
    ('targetRef', 'raw-code'),
    ('confirmationRef', 'raw-code'),
    ('name', 'bad\nname'),
    ('name', ''),
    ('name', 'x' * 513),
    ('memberCount', -1),
    ('memberCount', 100001),
    ('canDisband', 'true'),
  ]) {
    test('reject malformed confirmation $key $value', () {
      expect(
        () => CommunityDisbandPreview.parse(disbandPayload()..[key] = value),
        throwsFormatException,
      );
    });
  }
  test('mismatched organization confirmation fails closed', () async {
    final host = CommunityHarness(
      capabilities: ['communities.disbandPreview', 'communities.disband'],
      responses: {
        'communities.disbandPreview': disbandPayload()
          ..['targetRef'] = 'c' * 32,
      },
    );
    addTearDown(host.close);
    await expectLater(
      host.adapter.readDisband('a' * 32),
      throwsA(isA<CommunityFailure>()),
    );
  });
  test(
    'bad receipt is unknown and invalid password never reaches bridge',
    () async {
      final host = CommunityHarness(
        capabilities: ['communities.disbandPreview', 'communities.disband'],
        responses: {
          'communities.disband': {
            'schemaVersion': 1,
            'status': 'accepted',
            'error': 'outcomeUnknown',
          },
        },
      );
      addTearDown(host.close);
      for (final password in ['', ' ', 'x' * 4097]) {
        expect(
          (await host.adapter.disband('a' * 32, 'b' * 32, password)).error,
          'passwordInvalid',
        );
      }
      expect(host.requests, isEmpty);
      expect(
        (await host.adapter.disband('a' * 32, 'b' * 32, 'fixture')).status,
        'unknown',
      );
    },
  );
  test('controller sends once, clears confirmation, requires fresh read after rejection', () async {
    final port = DisbandFake()..writing = Completer<CommunityDisbandOutcome>();
    final model = CommunityDisbandController(port, 'a' * 32);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    await model.load();
    await model.confirm(' ');
    expect(port.writes, 0);
    final pending = model.confirm(' fixture ');
    await model.confirm('fixture');
    await model.load();
    expect(port.writes, 1);
    expect(port.reads, 1);
    port.writing!.complete(
      const CommunityDisbandOutcome('rejected', error: 'passwordInvalid'),
    );
    await pending;
    expect(model.preview, isNull);
    expect(model.canConfirm, isFalse);
    expect(model.error, 'passwordInvalid');
    expect(port.sentPassword, ' fixture ');
    await model.confirm('fixture');
    expect(port.writes, 1);
    await model.load();
    expect(model.canConfirm, isTrue);
  });
  test(
    'invalidated read or write never revives confirmation or reports success',
    () async {
      final port = DisbandFake()
        ..reading = Completer<CommunityDisbandPreview>();
      final model = CommunityDisbandController(port, 'a' * 32);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      final pending = model.load();
      port.changes.add(null);
      port.reading!.complete(port.preview);
      await pending;
      expect(model.preview, isNull);
      expect(model.invalidated, isTrue);
      final second = CommunityDisbandController(port, 'a' * 32);
      addTearDown(second.dispose);
      port.reading = null;
      port.writing = Completer<CommunityDisbandOutcome>();
      await second.load();
      final sent = second.confirm('fixture');
      port.changes.add(null);
      port.writing!.complete(const CommunityDisbandOutcome('accepted'));
      await sent;
      expect(second.outcome, isNull);
      expect(second.canConfirm, isFalse);
    },
  );
  test('lost response clears confirmation and does not auto retry', () async {
    final port = DisbandFake()..writing = Completer<CommunityDisbandOutcome>();
    final model = CommunityDisbandController(port, 'a' * 32);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    await model.load();
    final sent = model.confirm('fixture');
    port.writing!.completeError(StateError('lost'));
    await sent;
    expect(model.outcome?.status, 'unknown');
    expect(model.preview, isNull);
    await model.confirm('fixture');
    expect(port.writes, 1);
    expect(port.reads, 1);
  });
  test(
    'example disband removes exactly one organization from both directories',
    () async {
      final port = ExampleCommunities();
      addTearDown(port.close);
      await expectLater(
        port.readDisband('00000000000000000000000000000001'),
        throwsA(isA<CommunityFailure>()),
      );
      final old = await port.readDisband('00000000000000000000000000000002');
      final current = await port.readDisband(
        '00000000000000000000000000000002',
      );
      expect(
        (await port.disband(
          '00000000000000000000000000000002',
          old.confirmationRef,
          'example-only',
        )).error,
        'refreshRequired',
      );
      expect(
        (await port.disband(
          '00000000000000000000000000000001',
          current.confirmationRef,
          'example-only',
        )).error,
        'refreshRequired',
      );
      expect(
        (await port.disband(
          '00000000000000000000000000000002',
          current.confirmationRef,
          'example-only',
        )).status,
        'accepted',
      );
      expect(
        (await port.disband(
          '00000000000000000000000000000002',
          current.confirmationRef,
          'example-only',
        )).status,
        'rejected',
      );
      for (final view in ['mine', 'discover']) {
        final directory = await port.read(view: view, query: '');
        expect(
          directory.items.any(
            (v) => v.targetRef == '00000000000000000000000000000002',
          ),
          isFalse,
        );
        expect(
          directory.items.any(
            (v) => v.targetRef == '00000000000000000000000000000001',
          ),
          isTrue,
        );
      }
      await expectLater(
        port.execute('join', '00000000000000000000000000000002'),
        throwsA(isA<CommunityFailure>()),
      );
      expect(
        (await port.readWorkspace(
          '00000000000000000000000000000001',
          '',
          0,
        )).name,
        isNotEmpty,
      );
    },
  );
  test(
    'example never accepts a real credential and disposal removes capability',
    () async {
      final port = ExampleCommunities();
      final preview = await port.readDisband(
        '00000000000000000000000000000002',
      );
      expect(preview.isExample, isTrue);
      expect(
        (await port.disband(
          '00000000000000000000000000000002',
          preview.confirmationRef,
          'fixture-password',
        )).error,
        'passwordInvalid',
      );
      expect(
        (await port.readWorkspace(
          '00000000000000000000000000000002',
          '',
          0,
        )).access['isOwner'],
        isTrue,
      );
      await port.close();
      expect(port.disbandAvailable, isFalse);
      await expectLater(
        port.readDisband('00000000000000000000000000000002'),
        throwsA(isA<CommunityFailure>()),
      );
    },
  );
}
