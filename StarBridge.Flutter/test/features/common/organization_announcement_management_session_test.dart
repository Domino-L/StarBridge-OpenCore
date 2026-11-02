import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_announcement_management_port.dart';
import 'package:starbridge_flutter/features/common/organization_announcement_management_session.dart';
import 'package:starbridge_flutter/features/common/organization_announcement_outcomes_controller.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

import '../official_fleet/official_fleet_announcement_actual_wire_test.dart'
    show hostWire;

void main() {
  test(
    'synthetic typed UI port prepares then sends one immutable original intent',
    () async {
      final port = FixtureManagementPort();
      final outcomes = OrganizationAnnouncementOutcomesController(port);
      final session = OrganizationAnnouncementManagementSession(
        port,
        'officialFleet:7',
        outcomes: outcomes,
        requestId: () => 'c' * 32,
      );
      addTearDown(port.close);
      addTearDown(outcomes.dispose);
      addTearDown(session.dispose);
      await session.prepare();
      expect(session.canSubmit('publish'), isTrue);
      await session.submit(
        'publish',
        title: 'Native title',
        content: 'Native body',
      );
      expect(
        port.managed.single.toPayload(),
        hostWire('lifecycle-02-publish-request'),
      );
      expect(session.outcome!.status, 'accepted');
      expect(session.outcome!.revision, 1);
      expect(session.editor, isNull);
      expect(
        session.canSubmit('publish'),
        isFalse,
        reason: 'Past receipt is not editor authority',
      );
      expect(
        port.editorReads,
        1,
        reason: 'No automatic fresh editor or second mutation',
      );
    },
  );

  test('unknown/refresh/notFound keeps originalID and never rePOSTs', () async {
    final port = FixtureManagementPort()..failManage = true;
    final outcomes = OrganizationAnnouncementOutcomesController(port);
    var ids = 0;
    final session = OrganizationAnnouncementManagementSession(
      port,
      'officialFleet:7',
      outcomes: outcomes,
      requestId: () {
        ids++;
        return 'c' * 32;
      },
    );
    addTearDown(port.close);
    addTearDown(outcomes.dispose);
    addTearDown(session.dispose);
    await session.prepare();
    await session.submit(
      'publish',
      title: 'Native title',
      content: 'Native body',
    );
    final original = session.originalIntent;
    expect(session.unresolved, isTrue);
    await session.prepare();
    await session.submit(
      'publish',
      title: 'Different meaning',
      content: 'body',
    );
    await session.queryOriginal();
    expect(session.originalIntent, same(original));
    expect(session.unresolved, isTrue);
    expect(session.outcome!.error, 'notFound');
    expect(port.managed, hasLength(1));
    expect(ids, 1);
    expect(port.queries.single, ('c' * 32, 'officialFleet:7', 'publish'));
    port.queryAccepted = true;
    await session.queryOriginal();
    expect(session.unresolved, isFalse);
    expect(session.outcome!.status, 'accepted');
    expect(session.editor, isNull);
    expect(port.managed, hasLength(1));
  });

  test(
    'own pending blocks new source editor without opening the old workspace',
    () async {
      final port = FixtureManagementPort()
        ..pending = hostWire('lost-ack-02-pending-response');
      final outcomes = OrganizationAnnouncementOutcomesController(port);
      final session = OrganizationAnnouncementManagementSession(
        port,
        'officialFleet:7',
        outcomes: outcomes,
      );
      addTearDown(port.close);
      addTearDown(outcomes.dispose);
      addTearDown(session.dispose);
      await session.prepare();
      expect(session.error, 'outcomeUnknown');
      expect(session.editor, isNull);
      expect(port.editorReads, 0);
      expect(port.managed, isEmpty);
    },
  );

  test(
    'failed fresh editor and late source results never keep old permission',
    () async {
      final port = FixtureManagementPort();
      final outcomes = OrganizationAnnouncementOutcomesController(port);
      final session = OrganizationAnnouncementManagementSession(
        port,
        'officialFleet:7',
        outcomes: outcomes,
      );
      addTearDown(port.close);
      addTearDown(outcomes.dispose);
      addTearDown(session.dispose);
      await session.prepare();
      expect(session.editor, isNotNull);
      port.editorFailure = true;
      await session.prepare();
      expect(session.editor, isNull);
      expect(session.error, 'unavailable');
      port.editorFailure = false;
      final held = Completer<OrganizationAnnouncementEditor>();
      port.heldEditor = held;
      final reading = session.prepare();
      await Future<void>.delayed(Duration.zero);
      port.changes.add(null);
      held.complete(
        OrganizationAnnouncementEditor.parse(
          hostWire('lifecycle-01-editor-response'),
          'officialFleet:7',
        ),
      );
      await reading;
      expect(session.editor, isNull);
      expect(session.error, 'identityUnavailable');
    },
  );
}

/// Explicit synthetic UI port. It exercises coordinator behavior only; it is
/// not the real Bridge transport, permission provider or persistent journal.
class FixtureManagementPort implements OrganizationAnnouncementManagementPort {
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  bool managementAvailable = true;
  @override
  bool outcomesAvailable = true;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Stream<void> get managementInvalidations => changes.stream;
  bool failManage = false, editorFailure = false, queryAccepted = false;
  int editorReads = 0;
  Completer<OrganizationAnnouncementEditor>? heldEditor;
  Future<OrganizationAnnouncementPendingPage> Function(int)? pendingRead;
  Map<String, Object?> pending = {
    'schemaVersion': 1,
    'kind': 'pending',
    'offset': 0,
    'totalCount': 0,
    'items': [],
  };
  final managed = <OrganizationAnnouncementIntent>[];
  final pendingOffsets = <int>[];
  final queries = <(String, String?, String?)>[];
  @override
  Future<OrganizationAnnouncementEditor> readEditor(String sourceRef) async {
    editorReads++;
    if (editorFailure) throw const CommunityFailure('unavailable');
    if (heldEditor != null) return heldEditor!.future;
    return OrganizationAnnouncementEditor.parse(
      hostWire('lifecycle-01-editor-response'),
      sourceRef,
    );
  }

  @override
  Future<OrganizationAnnouncementOutcome> manage(
    OrganizationAnnouncementIntent intent,
  ) async {
    managed.add(intent);
    if (failManage) throw const CommunityFailure('unavailable');
    return OrganizationAnnouncementOutcome.parseManage(
      hostWire('lifecycle-02-publish-response'),
      intent,
    );
  }

  @override
  Future<OrganizationAnnouncementPendingPage> readPending({
    int offset = 0,
  }) async {
    pendingOffsets.add(offset);
    if (pendingRead != null) return pendingRead!(offset);
    return OrganizationAnnouncementPendingPage.parse(
      pending,
      expectedOffset: offset,
    );
  }

  @override
  Future<OrganizationAnnouncementOutcome> query(
    String requestId, {
    String? expectedSourceRef,
    String? expectedAction,
  }) async {
    queries.add((requestId, expectedSourceRef, expectedAction));
    return OrganizationAnnouncementOutcome.parseQuery(
      {
        'schemaVersion': 1,
        'kind': 'query',
        'requestId': requestId,
        'status': queryAccepted ? 'accepted' : 'unknown',
        if (queryAccepted) ...{
          'sourceRef': expectedSourceRef,
          'action': expectedAction,
          'revision': 1,
        } else
          'error': 'notFound',
      },
      requestId,
      expectedSourceRef: expectedSourceRef,
      expectedAction: expectedAction,
    );
  }

  @override
  Future<void> close() => changes.close();
}
