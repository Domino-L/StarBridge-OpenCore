import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_announcement_management_port.dart';
import 'package:starbridge_flutter/features/common/organization_announcement_management_session.dart';
import 'package:starbridge_flutter/features/common/organization_announcement_outcomes_controller.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_announcement_write_port.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_announcement_management.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import '../communities/bridge_communities_test.dart' show CommunityHarness;
import 'official_fleet_announcement_actual_wire_test.dart' show hostWire;

const _editor = BridgeOfficialFleetAnnouncementManagement.editorCommand;
const _manage = BridgeOfficialFleetAnnouncementManagement.manageCommand;
const _outcome = BridgeOfficialFleetAnnouncementManagement.outcomeCommand;
const _caps = BridgeOfficialFleetAnnouncementManagement.callableNames;
const _emptyPending = <String, Object?>{
  'schemaVersion': 1,
  'kind': 'pending',
  'offset': 0,
  'totalCount': 0,
  'items': [],
};

void main() {
  test(
    'generic or partial capability never admits official management',
    () async {
      for (final caps in <List<String>>[
        ['communities.commands'],
        [_editor, _manage],
        [_outcome],
        [],
      ]) {
        final host = CommunityHarness(capabilities: caps);
        final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
        expect(port.managementAvailable, isFalse);
        expect(
          host.adapter.supportsOfficialAnnouncementCommand(
            'officialFleet.unknown',
          ),
          isFalse,
        );
        final intent = OrganizationAnnouncementIntent.parse(
          hostWire('lifecycle-02-publish-request'),
        );
        expect((await port.manage(intent)).status, 'rejected');
        expect(host.requests, isEmpty);
        if (!caps.contains(_editor)) {
          await expectLater(
            host.adapter.sendRequest(
              _editor,
              hostWire('lifecycle-01-editor-request'),
            ),
            throwsA(isA<CommunityFailure>()),
          );
          expect(
            host.requests,
            isEmpty,
            reason: 'Exact map rejects generic communities.commands fallback',
          );
        }
        await port.close();
        await host.close();
      }
    },
  );

  for (final (editorScene, actionScene) in [
    ('lifecycle-01-editor', 'lifecycle-02-publish'),
    ('lifecycle-03-editor', 'lifecycle-04-edit'),
    ('lifecycle-05-editor', 'lifecycle-06-withdraw'),
  ]) {
    test(
      'actual $actionScene payload replay through the single existing transport',
      () async {
        final host = CommunityHarness(
          capabilities: [..._caps],
          responses: {
            _editor: hostWire('$editorScene-response'),
            _manage: hostWire('$actionScene-response'),
          },
        );
        addTearDown(host.close);
        final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
        addTearDown(port.close);
        expect(
          port.managementAvailable,
          isTrue,
          reason: 'Protocol support only; actual editor still required',
        );
        final editorRequest = hostWire('$editorScene-request');
        final editor = await port.readEditor(
          editorRequest['sourceRef'] as String,
        );
        final intent = OrganizationAnnouncementIntent.parse(
          hostWire('$actionScene-request'),
        );
        expect(editor.editRef, intent.editRef);
        final result = await port.manage(intent);
        expect(result.status, 'accepted');
        expect(result.revision, editor.revision + 1);
        expect(
          host.requests.where((r) => r.name == _editor).single.payload,
          editorRequest,
        );
        expect(
          host.requests.where((r) => r.name == _manage).single.payload,
          hostWire('$actionScene-request'),
        );
        expect(
          host.requests.where((r) => r.name == 'account.getCurrent'),
          hasLength(2),
        );
        expect(host.requests.where((r) => r.name == _outcome), isEmpty);
      },
    );
  }

  for (final scene in ['lost-ack', 'local-ack']) {
    test(
      'actual $scene unknown remains originalID, own query needs no workspace/editor',
      () async {
        final responses = <String, Map<String, Object?>>{
          _manage: hostWire('$scene-01-unknown-response'),
          _outcome: hostWire('$scene-02-pending-response'),
        };
        final host = CommunityHarness(
          capabilities: [..._caps],
          responses: responses,
        );
        addTearDown(host.close);
        final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
        addTearDown(port.close);
        final intent = OrganizationAnnouncementIntent.parse(
          hostWire('$scene-01-unknown-request'),
        );
        final unknown = await port.manage(intent);
        expect(unknown.unresolved, isTrue);
        expect(
          host.requests.where((r) => r.name == _manage).single.payload,
          hostWire('$scene-01-unknown-request'),
        );
        host.session.acceptHostCapabilities([_outcome]);
        expect(port.managementAvailable, isFalse);
        expect(port.outcomesAvailable, isTrue);
        final pending = await port.readPending();
        expect(pending.items.single.requestId, intent.requestId);
        responses[_outcome] = hostWire('$scene-03-restarted-query-response');
        final result = await port.query(
          intent.requestId,
          expectedSourceRef: intent.sourceRef,
          expectedAction: intent.action,
        );
        expect(result.status, 'accepted');
        expect(result.requestId, intent.requestId);
        final requests = host.requests
            .where((r) => r.name == _outcome)
            .toList();
        expect(requests[0].payload, hostWire('$scene-02-pending-request'));
        expect(
          requests[1].payload,
          hostWire('$scene-03-restarted-query-request'),
        );
        expect(host.requests.where((r) => r.name == _manage), hasLength(1));
        expect(
          host.requests.where(
            (r) => r.name == _editor || r.name == 'officialFleet.communication',
          ),
          isEmpty,
        );
      },
    );
  }

  test('legacy cannot use three new routes; ordinary legacy community write stays accepted', () async {
    final host = CommunityHarness(
      legacy: true,
      capabilities: [..._caps, 'communities.manageAnnouncements'],
      responses: {
        _editor: hostWire('lifecycle-01-editor-response'),
        'communities.manageAnnouncements': {
          'schemaVersion': 1,
          'targetRef': 'a' * 32,
          'requestId': 'b' * 32,
          'action': 'publish',
          'status': 'accepted',
          'revision': 10,
        },
      },
    );
    addTearDown(host.close);
    final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
    addTearDown(port.close);
    await expectLater(
      port.readEditor('officialFleet:7'),
      throwsA(isA<CommunityFailure>()),
    );
    await expectLater(port.query('b' * 32), throwsA(isA<CommunityFailure>()));
    expect(host.requests.where((r) => _caps.contains(r.name)), isEmpty);
    final ordinary = await host.adapter.manageAnnouncement(
      CommunityAnnouncementIntent(
        targetRef: 'a' * 32,
        requestId: 'b' * 32,
        action: 'publish',
        title: 'Title',
        content: 'Body',
      ),
    );
    expect(ordinary.status, 'accepted');
    expect(
      host.requests.where((r) => r.name == 'communities.manageAnnouncements'),
      hasLength(1),
    );
  });

  test(
    'management cap revoked during account admission sends no mutation',
    () async {
      final host = CommunityHarness(
        capabilities: [..._caps],
        holdNames: {'account.getCurrent'},
        responses: {_manage: hostWire('lifecycle-02-publish-response')},
      );
      addTearDown(host.close);
      final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
      addTearDown(port.close);
      final intent = OrganizationAnnouncementIntent.parse(
        hostWire('lifecycle-02-publish-request'),
      );
      final sending = port.manage(intent);
      await host.readArrived.future.timeout(const Duration(seconds: 1));
      expect(host.requests.map((request) => request.name), [
        'account.getCurrent',
      ]);
      final originalAccountRead = host.requests.single;
      expect(
        host.requests.where((request) => request.name == _manage),
        isEmpty,
      );

      final retired = port.managementInvalidations.first;
      host.session.acceptHostCapabilities([_outcome]);
      await retired.timeout(const Duration(seconds: 1));
      expect(port.managementAvailable, isFalse);
      expect(port.outcomesAvailable, isTrue);
      expect(host.requests.map((request) => request.name), [
        'account.getCurrent',
      ]);

      await host.reply(originalAccountRead);
      final result = await sending;
      expect(result.requestId, intent.requestId);
      expect(result.sourceRef, intent.sourceRef);
      expect(result.action, intent.action);
      expect(result.status, isNot('accepted'));
      expect(result.revision, isNull);
      expect(
        host.requests.where((request) => request.name == 'account.getCurrent'),
        hasLength(1),
      );
      expect(
        host.requests.where((request) => request.name == _editor),
        isEmpty,
      );
      expect(
        host.requests.where((request) => request.name == _outcome),
        isEmpty,
      );
      expect(
        host.requests.where((request) => request.name == _manage).length,
        0,
        reason:
            'A revoked management capability must stop before command dispatch',
      );
    },
  );

  test(
    'capability restoration cannot revive management held at account admission',
    () async {
      final host = CommunityHarness(
        capabilities: [..._caps],
        holdNames: {'account.getCurrent'},
        responses: {_manage: hostWire('lifecycle-02-publish-response')},
      );
      addTearDown(host.close);
      final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
      addTearDown(port.close);
      final intent = OrganizationAnnouncementIntent.parse(
        hostWire('lifecycle-02-publish-request'),
      );
      final sending = port.manage(intent);
      await host.readArrived.future.timeout(const Duration(seconds: 1));
      expect(host.requests.map((request) => request.name), [
        'account.getCurrent',
      ]);
      final accountRead = host.requests.single;
      final retired = port.managementInvalidations.first;
      host.session.acceptHostCapabilities([_outcome]);
      await retired.timeout(const Duration(seconds: 1));
      final restored = port.managementInvalidations.first;
      host.session.acceptHostCapabilities(_caps);
      await restored.timeout(const Duration(seconds: 1));
      expect(port.managementAvailable, isTrue);
      await host.reply(accountRead);
      final result = await sending;
      expect(result.requestId, intent.requestId);
      expect(result.sourceRef, intent.sourceRef);
      expect(result.action, intent.action);
      expect(result.status, isNot('accepted'));
      expect(result.revision, isNull);
      expect(
        host.requests.where((request) => request.name == 'account.getCurrent'),
        hasLength(1),
      );
      expect(
        host.requests.where((request) => request.name == _outcome),
        isEmpty,
      );
      expect(
        host.requests.where((request) => request.name == _manage).length,
        0,
      );
    },
  );

  test('facade close during account admission prevents a command without closing transport', () async {
    final host = CommunityHarness(
      capabilities: [..._caps],
      holdNames: {'account.getCurrent'},
      responses: {_manage: hostWire('lifecycle-02-publish-response')},
    );
    addTearDown(host.close);
    final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
    addTearDown(port.close);
    final intent = OrganizationAnnouncementIntent.parse(
      hostWire('lifecycle-02-publish-request'),
    );
    final sending = port.manage(intent);
    await host.readArrived.future.timeout(const Duration(seconds: 1));
    expect(host.requests.map((request) => request.name), [
      'account.getCurrent',
    ]);
    final accountRead = host.requests.single;
    await port.close();
    expect(host.adapter.isClosed, isFalse);
    await host.reply(accountRead);
    final result = await sending;
    expect(result.requestId, intent.requestId);
    expect(result.sourceRef, intent.sourceRef);
    expect(result.action, intent.action);
    expect(result.status, isNot('accepted'));
    expect(result.revision, isNull);
    expect(
      host.requests.where((request) => request.name == 'account.getCurrent'),
      hasLength(1),
    );
    expect(host.requests.where((request) => request.name == _outcome), isEmpty);
    expect(host.requests.where((request) => request.name == _manage).length, 0);
  });

  test(
    'own query survives management cap loss while its account admission waits',
    () async {
      final host = CommunityHarness(
        capabilities: [..._caps],
        holdNames: {'account.getCurrent'},
        responses: {_outcome: hostWire('lost-ack-03-restarted-query-response')},
      );
      addTearDown(host.close);
      final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
      addTearDown(port.close);
      final intent = OrganizationAnnouncementIntent.parse(
        hostWire('lost-ack-01-unknown-request'),
      );
      final reading = port.query(
        intent.requestId,
        expectedSourceRef: intent.sourceRef,
        expectedAction: intent.action,
      );
      await host.readArrived.future.timeout(const Duration(seconds: 1));
      expect(host.requests.map((request) => request.name), [
        'account.getCurrent',
      ]);
      final accountRead = host.requests.single;
      final retired = port.managementInvalidations.first;
      host.session.acceptHostCapabilities([_outcome]);
      await retired.timeout(const Duration(seconds: 1));
      expect(port.managementAvailable, isFalse);
      expect(port.outcomesAvailable, isTrue);
      await host.reply(accountRead);
      final result = await reading;
      expect(result.status, 'accepted');
      expect(result.requestId, intent.requestId);
      expect(host.requests.map((request) => request.name), [
        'account.getCurrent',
        _outcome,
      ]);
      expect(
        host.requests.last.payload,
        hostWire('lost-ack-03-restarted-query-request'),
      );
      expect(
        host.requests.where(
          (request) => request.name == _manage || request.name == _editor,
        ),
        isEmpty,
      );
    },
  );

  test(
    'management cap loss retires editor without retiring a valid own query',
    () async {
      final held = <String>{};
      final responses = <String, Map<String, Object?>>{
        _outcome: _emptyPending,
        _editor: hostWire('lifecycle-01-editor-response'),
      };
      final host = CommunityHarness(
        capabilities: [..._caps],
        holdNames: held,
        responses: responses,
      );
      addTearDown(host.close);
      final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
      addTearDown(port.close);
      final outcomes = OrganizationAnnouncementOutcomesController(port);
      addTearDown(outcomes.dispose);
      final session = OrganizationAnnouncementManagementSession(
        port,
        'officialFleet:7',
        outcomes: outcomes,
      );
      addTearDown(session.dispose);
      await session.prepare();
      expect(session.canSubmit('publish'), isTrue);
      held.add(_outcome);
      responses[_outcome] = hostWire('lost-ack-03-restarted-query-response');
      final original = OrganizationAnnouncementIntent.parse(
        hostWire('lost-ack-01-unknown-request'),
      );
      final query = outcomes.query(original.requestId, original: original);
      await host.readArrived.future;
      final retired = port.managementInvalidations.first;
      host.session.acceptHostCapabilities([_outcome]);
      await retired;
      expect(session.editor, isNull);
      expect(session.canSubmit('publish'), isFalse);
      expect(outcomes.queryingRequestId, original.requestId);
      await host.reply(host.requests.lastWhere((r) => r.name == _outcome));
      expect((await query)!.status, 'accepted');
      expect(
        outcomes.results,
        isEmpty,
        reason:
            'Session-only recovery returns without growing snapshot history',
      );
      final restored = port.managementInvalidations.first;
      host.session.acceptHostCapabilities(_caps);
      await restored;
      expect(session.editor, isNull);
      expect(
        session.canSubmit('publish'),
        isFalse,
        reason: 'Capability restoration cannot resurrect an old editor',
      );
    },
  );

  test('outcome cap revocation retires its late response even after capability restoration', () async {
    final host = CommunityHarness(
      capabilities: [_outcome],
      holdNames: {_outcome},
      responses: {_outcome: hostWire('lost-ack-03-restarted-query-response')},
    );
    addTearDown(host.close);
    final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
    addTearDown(port.close);
    final intent = OrganizationAnnouncementIntent.parse(
      hostWire('lost-ack-01-unknown-request'),
    );
    final reading = port.query(
      intent.requestId,
      expectedSourceRef: intent.sourceRef,
      expectedAction: intent.action,
    );
    final rejected = expectLater(reading, throwsA(isA<CommunityFailure>()));
    await host.readArrived.future;
    final retired = port.invalidations.first;
    host.session.acceptHostCapabilities([]);
    await retired;
    final restored = port.invalidations.first;
    host.session.acceptHostCapabilities([_outcome]);
    await restored;
    await host.reply(host.requests.lastWhere((r) => r.name == _outcome));
    await rejected;
    expect(host.requests.where((r) => r.name == _manage), isEmpty);
  });

  test('late accepted write after management-cap retirement stays unknown on originalID', () async {
    final host = CommunityHarness(
      capabilities: [..._caps],
      holdNames: {_manage},
      responses: {_manage: hostWire('lifecycle-02-publish-response')},
    );
    addTearDown(host.close);
    final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
    addTearDown(port.close);
    final intent = OrganizationAnnouncementIntent.parse(
      hostWire('lifecycle-02-publish-request'),
    );
    final sending = port.manage(intent);
    await host.readArrived.future;
    final retired = port.managementInvalidations.first;
    host.session.acceptHostCapabilities([_outcome]);
    await retired;
    await host.reply(host.requests.singleWhere((r) => r.name == _manage));
    final result = await sending;
    expect(result.unresolved, isTrue);
    expect(result.requestId, intent.requestId);
    expect(result.revision, isNull);
    expect(host.requests.where((r) => r.name == _manage), hasLength(1));
    expect(host.requests.where((r) => r.name == _outcome), isEmpty);
  });

  test('existing connection-mode coordinator retires a delayed editor without a second worker', () async {
    final host = CommunityHarness(
      capabilities: [..._caps],
      holdNames: {_editor},
      responses: {_editor: hostWire('lifecycle-01-editor-response')},
    );
    addTearDown(host.close);
    final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
    addTearDown(port.close);
    final reading = port.readEditor('officialFleet:7');
    final rejected = expectLater(reading, throwsA(isA<CommunityFailure>()));
    await host.readArrived.future;
    final retired = port.managementInvalidations.first;
    await host.session.runConnectionModeChange(() async {});
    await retired;
    await host.reply(host.requests.singleWhere((r) => r.name == _editor));
    await rejected;
    expect(host.requests.where((r) => r.name == _manage), isEmpty);
  });

  test('later source read retires an older delayed editor', () async {
    final held = <String>{_editor};
    final responses = <String, Map<String, Object?>>{
      _editor: hostWire('lifecycle-01-editor-response'),
    };
    final host = CommunityHarness(
      capabilities: [..._caps],
      holdNames: held,
      responses: responses,
    );
    addTearDown(host.close);
    final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
    addTearDown(port.close);
    final old = port.readEditor('officialFleet:7');
    final rejected = expectLater(old, throwsA(isA<CommunityFailure>()));
    await host.readArrived.future;
    final oldRequest = host.requests.lastWhere((r) => r.name == _editor);
    held.clear();
    responses[_editor] = {
      ...hostWire('lifecycle-01-editor-response'),
      'sourceRef': 'officialFleet:8',
      'editRef': 'f' * 32,
    };
    expect(
      (await port.readEditor('officialFleet:8')).sourceRef,
      'officialFleet:8',
    );
    await host.reply(oldRequest);
    await rejected;
  });

  test('account generation change retires a delayed editor', () async {
    final host = CommunityHarness(
      capabilities: [..._caps],
      holdNames: {_editor},
      responses: {_editor: hostWire('lifecycle-01-editor-response')},
    );
    addTearDown(host.close);
    final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
    addTearDown(port.close);
    final reading = port.readEditor('officialFleet:7');
    final rejected = expectLater(reading, throwsA(isA<CommunityFailure>()));
    await host.readArrived.future;
    final retired = port.managementInvalidations.first;
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
    await retired;
    await rejected;
    expect(host.requests.where((r) => r.name == _manage), isEmpty);
  });

  test(
    'same-code Host error after dispatch stays unknown on originalID',
    () async {
      final host = CommunityHarness(
        capabilities: [..._caps],
        error: 'bridge.official_announcement_not_dispatched',
      );
      addTearDown(host.close);
      final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
      addTearDown(port.close);
      final intent = OrganizationAnnouncementIntent.parse(
        hostWire('lifecycle-02-publish-request'),
      );
      final result = await port.manage(intent);
      expect(result.status, 'unknown');
      expect(result.requestId, intent.requestId);
      expect(result.sourceRef, intent.sourceRef);
      expect(result.action, intent.action);
      expect(result.revision, isNull);
      expect(result.error, 'outcomeUnknown');
      expect(host.requests.map((request) => request.name), [
        'account.getCurrent',
        _manage,
      ]);
      expect(
        host.requests.where((request) => request.name == _manage),
        hasLength(1),
      );
      expect(host.requests.last.payload, intent.toPayload());
      expect(
        host.requests.where((request) => request.name == _outcome),
        isEmpty,
      );
    },
  );

  for (final field in ['requestId', 'schemaVersion', 'revision']) {
    test(
      'malformed manage $field stays unknown with one command, never a replay',
      () async {
        final response = hostWire('lifecycle-02-publish-response');
        response[field] = field == 'requestId'
            ? 'f' * 32
            : field == 'schemaVersion'
            ? 2
            : null;
        final host = CommunityHarness(
          capabilities: [..._caps],
          responses: {_manage: response},
        );
        addTearDown(host.close);
        final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
        addTearDown(port.close);
        final intent = OrganizationAnnouncementIntent.parse(
          hostWire('lifecycle-02-publish-request'),
        );
        final result = await port.manage(intent);
        expect(result.unresolved, isTrue);
        expect(result.requestId, intent.requestId);
        expect(result.error, 'outcomeUnknown');
        expect(host.requests.where((r) => r.name == _manage), hasLength(1));
        expect(host.requests.where((r) => r.name == _outcome), isEmpty);
      },
    );
  }

  test('closing facade releases own subscriptions and leaves borrowed community transport usable', () async {
    final host = CommunityHarness(capabilities: [..._caps, 'communities.read']);
    addTearDown(host.close);
    final port = BridgeOfficialFleetAnnouncementManagement(host.adapter);
    await port.close();
    expect(port.managementAvailable, isFalse);
    expect(port.outcomesAvailable, isFalse);
    expect(host.adapter.isClosed, isFalse);
    final page = await host.adapter.read(view: 'mine', query: '');
    expect(page.items, isEmpty);
    expect(
      host.requests.where((r) => r.name == 'communities.read'),
      hasLength(1),
    );
  });
}
