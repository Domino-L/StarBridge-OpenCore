import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_logs_port.dart';
import 'package:starbridge_flutter/features/communities/community_logs_controller.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';

import 'bridge_communities_test.dart' show CommunityHarness;

Map<String, Object?> logsPayload() => {
  'schemaVersion': 1,
  'targetRef': 'a' * 32,
  'name': 'Organization',
  'canDelete': true,
  'type': 'All',
  'query': '',
  'offset': 0,
  'next': null,
  'totalCount': 1,
  'matchedCount': 1,
  'fetchedAt': '2026-09-07T00:00:00Z',
  'items': [
    {
      'logRef': 'b' * 32,
      'type': '成员',
      'title': '成员加入',
      'detail': 'Visible detail',
      'timestamp': null,
      'endTimestamp': null,
      'occurrenceCount': 3,
    },
  ],
};

final class LogsFake implements CommunityLogsPort {
  final changes = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  bool logsAvailable = true;
  @override
  bool logDeletionAvailable = true;
  int reads = 0, writes = 0;
  String? failure;
  bool canDelete = true;
  bool empty = false;
  Completer<CommunityLogPage>? pending;
  Completer<CommunityLogOutcome>? writePending;
  CommunityLogOutcome outcome = const CommunityLogOutcome('accepted');
  @override
  Future<CommunityLogPage> readLogs(
    String targetRef,
    String type,
    String query,
    int offset,
  ) async {
    reads++;
    if (pending != null) return pending!.future;
    if (failure != null) throw CommunityFailure(failure!);
    final value = logsPayload()..['canDelete'] = canDelete;
    if (empty) {
      value['items'] = [];
      value['matchedCount'] = 0;
      value['totalCount'] = 0;
    }
    value['type'] = type;
    value['query'] = query;
    value['offset'] = offset;
    return CommunityLogPage.parse(value);
  }

  @override
  Future<CommunityLogOutcome> deleteLog(String targetRef, String logRef) async {
    writes++;
    if (writePending != null) return writePending!.future;
    if (outcome.status == 'accepted') empty = true;
    return outcome;
  }
}

void main() {
  test('Bridge logs negotiate separately and preserve exact scope', () async {
    final host = CommunityHarness(
      capabilities: ['communities.logs', 'communities.deleteLog'],
      responses: {
        'communities.logs': logsPayload(),
        'communities.deleteLog': {'schemaVersion': 1, 'status': 'accepted'},
      },
    );
    addTearDown(host.close);
    expect(host.adapter.logsAvailable, isTrue);
    final page = await host.adapter.readLogs('a' * 32, 'All', '', 0);
    expect(page.items.single.timestamp, isNull);
    expect(page.items.single.occurrenceCount, 3);
    expect(
      (await host.adapter.deleteLog(
        page.targetRef,
        page.items.single.logRef,
      )).status,
      'accepted',
    );
    expect(host.requests.last.payload, {
      'schemaVersion': 1,
      'targetRef': 'a' * 32,
      'logRef': 'b' * 32,
    });
    expect(host.requests.last.accountContext?.subject, 'test-subject');
  });
  test('old Host cannot expose or send log commands', () async {
    final host = CommunityHarness(capabilities: ['communities.commands']);
    addTearDown(host.close);
    expect(host.adapter.logsAvailable, isFalse);
    expect(host.adapter.logDeletionAvailable, isFalse);
    expect(
      (await host.adapter.deleteLog('a' * 32, 'b' * 32)).status,
      'rejected',
    );
    expect(host.requests, isEmpty);
  });
  test('malformed success receipt is unknown', () async {
    final host = CommunityHarness(
      capabilities: ['communities.logs', 'communities.deleteLog'],
      responses: {
        'communities.deleteLog': {'schemaVersion': 2, 'status': 'accepted'},
      },
    );
    addTearDown(host.close);
    expect(
      (await host.adapter.deleteLog('a' * 32, 'b' * 32)).status,
      'unknown',
    );
  });
  for (final (key, value) in <(String, Object?)>[
    ('schemaVersion', 2),
    ('targetRef', 'source-id'),
    ('canDelete', 'yes'),
    ('type', '任务'),
    ('next', 20),
    ('matchedCount', 0),
    ('totalCount', 100001),
    ('fetchedAt', 'invalid'),
    ('query', 'bad\n'),
    ('extra', 'x' * (960 * 1024)),
  ]) {
    test('reject malformed log page $key', () {
      expect(
        () => CommunityLogPage.parse(logsPayload()..[key] = value),
        throwsFormatException,
      );
    });
  }
  test('duplicate entries and reversed time ranges are rejected', () {
    final payload = logsPayload();
    final rows = payload['items'] as List;
    rows.add(rows.first);
    payload['totalCount'] = 2;
    payload['matchedCount'] = 2;
    expect(() => CommunityLogPage.parse(payload), throwsFormatException);
    final other = logsPayload();
    final row = (other['items'] as List).single as Map;
    row['timestamp'] = '2026-09-07T00:00:00Z';
    row['endTimestamp'] = '2026-09-06T00:00:00Z';
    expect(() => CommunityLogPage.parse(other), throwsFormatException);
  });
  test(
    'selection and cancellation do not delete; accepted refreshes real page',
    () async {
      final port = LogsFake();
      final model = CommunityLogsController(port, 'a' * 32);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      await model.load();
      model.selectForDeletion(model.snapshot!.items.single);
      expect(port.writes, 0);
      model.cancelDeletion();
      await model.confirmDeletion();
      expect(port.writes, 0);
      model.selectForDeletion(model.snapshot!.items.single);
      await model.confirmDeletion();
      expect(port.writes, 1);
      expect(port.reads, 2);
      expect(model.snapshot!.items, isEmpty);
      expect(model.lastOutcome, 'accepted');
      await model.confirmDeletion();
      expect(port.writes, 1);
    },
  );
  test(
    'unknown result requires fresh read and selection; no automatic resend',
    () async {
      final port = LogsFake()
        ..outcome = const CommunityLogOutcome(
          'unknown',
          error: 'outcomeUnknown',
        );
      final model = CommunityLogsController(port, 'a' * 32);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      await model.load();
      model.selectForDeletion(model.snapshot!.items.single);
      await model.confirmDeletion();
      expect(model.error, 'outcomeUnknown');
      expect(model.snapshot, isNull);
      expect(model.pendingDeletion, isNull);
      await model.confirmDeletion();
      expect(port.writes, 1);
      await model.load();
      await model.confirmDeletion();
      expect(port.writes, 1);
    },
  );
  test('permission denial clears private content and selection', () async {
    final port = LogsFake();
    final model = CommunityLogsController(port, 'a' * 32);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    await model.load();
    model.selectForDeletion(model.snapshot!.items.single);
    port.failure = 'notAllowed';
    await model.load();
    expect(model.invalidated, isTrue);
    expect(model.snapshot, isNull);
    expect(model.pendingDeletion, isNull);
    expect(model.loading, isFalse);
    await model.confirmDeletion();
    expect(port.writes, 0);
  });
  test('read-only access never permits selection', () async {
    final port = LogsFake()..canDelete = false;
    final model = CommunityLogsController(port, 'a' * 32);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    await model.load();
    model.selectForDeletion(model.snapshot!.items.single);
    expect(model.pendingDeletion, isNull);
    await model.confirmDeletion();
    expect(port.writes, 0);
  });
  test('late read after identity invalidation cannot restore logs', () async {
    final port = LogsFake()..pending = Completer<CommunityLogPage>();
    final model = CommunityLogsController(port, 'a' * 32);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    final read = model.load();
    port.changes.add(null);
    port.pending!.complete(CommunityLogPage.parse(logsPayload()));
    await read;
    expect(model.snapshot, isNull);
    expect(model.invalidated, isTrue);
    expect(model.loading, isFalse);
  });
  test('late delete reply after identity invalidation cannot refresh old organization', () async {
    final port = LogsFake();
    final model = CommunityLogsController(port, 'a' * 32);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    await model.load();
    model.selectForDeletion(model.snapshot!.items.single);
    port.writePending = Completer<CommunityLogOutcome>();
    final write = model.confirmDeletion();
    await model.confirmDeletion();
    expect(port.writes, 1);
    port.changes.add(null);
    port.writePending!.complete(const CommunityLogOutcome('accepted'));
    await write;
    expect(port.reads, 1);
    expect(model.snapshot, isNull);
    expect(model.pendingDeletion, isNull);
  });
}
