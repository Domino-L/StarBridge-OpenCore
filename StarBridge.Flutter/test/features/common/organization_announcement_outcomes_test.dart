import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/organization_announcement_management_port.dart';
import 'package:starbridge_flutter/features/common/organization_announcement_outcomes_controller.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

import 'organization_announcement_management_session_test.dart'
    show FixtureManagementPort;
import '../official_fleet/official_fleet_announcement_actual_wire_test.dart'
    show hostWire;

void main() {
  test(
    '128 pending is complete only after exactly7 bounded typed pages',
    () async {
      final port = FixtureManagementPort()
        ..pendingRead = (offset) async => pendingPage(offset, 128);
      final controller = OrganizationAnnouncementOutcomesController(port);
      addTearDown(port.close);
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.complete, isTrue);
      expect(controller.totalCount, 128);
      expect(port.pendingOffsets, [0, 20, 40, 60, 80, 100, 120]);
      expect(port.queries, isEmpty);
      expect(port.managed, isEmpty);
    },
  );

  test(
    'two disjoint full pending generations retain results only for current128',
    () async {
      var batch = 0;
      final port = FixtureManagementPort()
        ..pendingRead = (offset) async =>
            pendingPage(offset, 128, idBase: batch * 128);
      final controller = OrganizationAnnouncementOutcomesController(port);
      addTearDown(port.close);
      addTearDown(controller.dispose);
      await controller.refresh();
      final first = controller.items.map((row) => row.requestId).toSet();
      for (final row in controller.items) {
        final result = await controller.query(row.requestId);
        expect(result!.unresolved, isTrue);
      }
      expect(controller.results.keys.toSet(), first);
      batch = 1;
      await controller.refresh();
      expect(controller.complete, isTrue);
      final second = controller.items.map((row) => row.requestId).toSet();
      expect(second.intersection(first), isEmpty);
      for (final row in controller.items) {
        final result = await controller.query(row.requestId);
        expect(result!.unresolved, isTrue);
      }
      expect(port.pendingOffsets, [
        0,
        20,
        40,
        60,
        80,
        100,
        120,
        0,
        20,
        40,
        60,
        80,
        100,
        120,
      ]);
      expect(port.queries, hasLength(256));
      expect(controller.totalCount, 128);
      expect(
        controller.results,
        hasLength(128),
        reason: 'Two complete128-item generations must not grow retained results to256',
      );
      expect(
        controller.results.keys.toSet(),
        second,
        reason: 'Current bounded snapshot must replace historical query-result membership',
      );
      expect(port.managed, isEmpty);
    },
  );

  test('session-only original query returns outcome without accumulating snapshot history', () async {
    final port = FixtureManagementPort();
    final controller = OrganizationAnnouncementOutcomesController(port);
    addTearDown(port.close);
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.totalCount, 0);
    final original = OrganizationAnnouncementIntent.parse(
      hostWire('lifecycle-02-publish-request'),
    );
    final result = await controller.query(
      original.requestId,
      original: original,
    );
    expect(result!.requestId, original.requestId);
    expect(result.unresolved, isTrue);
    expect(result.error, 'notFound');
    expect(
      controller.results,
      isEmpty,
      reason: 'The caller session owns this returned outcome; it is not a pending-snapshot row',
    );
    expect(controller.totalCount, 0);
    expect(port.managed, isEmpty);
  });

  test(
    'changed total/duplicate across pages is unavailable, never a partial zero',
    () async {
      for (final duplicate in [false, true]) {
        final port = FixtureManagementPort()
          ..pendingRead = (offset) async => pendingPage(
            offset,
            offset > 0 && !duplicate ? 39 : 40,
            duplicate: duplicate && offset > 0,
          );
        final controller = OrganizationAnnouncementOutcomesController(port);
        await controller.refresh();
        expect(controller.complete, isFalse);
        expect(controller.totalCount, isNull);
        expect(controller.error, 'dataInvalid');
        expect(controller.items, isEmpty);
        controller.dispose();
        await port.close();
      }
    },
  );

  test(
    'failed scan preserves prior rows as incomplete, while known empty is zero',
    () async {
      final port = FixtureManagementPort()
        ..pending = hostWire('lost-ack-02-pending-response');
      final controller = OrganizationAnnouncementOutcomesController(port);
      addTearDown(port.close);
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.totalCount, 1);
      final previous = await controller.query(
        controller.items.single.requestId,
      );
      expect(controller.results.values.single, same(previous));
      port.pendingRead = (_) async =>
          throw const CommunityFailure('unavailable');
      await controller.refresh();
      expect(controller.items, hasLength(1));
      expect(controller.totalCount, isNull);
      expect(controller.complete, isFalse);
      expect(
        controller.results.values.single,
        same(previous),
        reason: 'Failed scan keeps the old incomplete snapshot and its results',
      );
      port.pendingRead = (offset) async => pendingPage(offset, 0);
      await controller.refresh();
      expect(controller.totalCount, 0);
      expect(controller.complete, isTrue);
    },
  );

  test(
    'reconstructed own pending only queries originalID; notFound stays unknown',
    () async {
      final port = FixtureManagementPort()
        ..pending = hostWire('lost-ack-02-pending-response');
      final controller = OrganizationAnnouncementOutcomesController(port);
      addTearDown(port.close);
      addTearDown(controller.dispose);
      await controller.refresh();
      final row = controller.items.single;
      final result = await controller.query(row.requestId);
      expect(result!.status, 'unknown');
      expect(result.error, 'notFound');
      expect(controller.hasUnresolvedSource(row.sourceRef), isTrue);
      expect(port.queries.single, (row.requestId, row.sourceRef, row.action));
      expect(port.managed, isEmpty);
      expect(port.editorReads, 0);
      await controller.query('f' * 32);
      expect(
        port.queries,
        hasLength(1),
        reason: 'Unknown local intent is not probed or rePOSTed',
      );
    },
  );

  test(
    'account invalidation discards late pending without publishing old rows',
    () async {
      final held = Completer<OrganizationAnnouncementPendingPage>();
      final port = FixtureManagementPort()..pendingRead = (_) => held.future;
      final controller = OrganizationAnnouncementOutcomesController(port);
      addTearDown(port.close);
      addTearDown(controller.dispose);
      final loading = controller.refresh();
      port.changes.add(null);
      held.complete(pendingPage(0, 1));
      await loading;
      expect(controller.items, isEmpty);
      expect(controller.complete, isFalse);
      expect(controller.error, 'identityUnavailable');
    },
  );
}

OrganizationAnnouncementPendingPage pendingPage(
  int offset,
  int total, {
  bool duplicate = false,
  int idBase = 0,
}) {
  final count = (total - offset).clamp(0, 20).toInt();
  return OrganizationAnnouncementPendingPage.parse({
    'schemaVersion': 1,
    'kind': 'pending',
    'offset': offset,
    'totalCount': total,
    if (offset + count < total) 'next': offset + 20,
    'items': List.generate(
      count,
      (index) => {
        'requestId': (idBase + index + (duplicate ? 0 : offset))
            .toRadixString(16)
            .padLeft(32, '0'),
        'sourceRef': 'officialFleet:7',
        'action': 'edit',
        'requestedAt': '2026-10-17T08:41:43.5653188+00:00',
        'status': 'unknown',
      },
    ),
  }, expectedOffset: offset);
}
