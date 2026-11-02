import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_chat_attention.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

import 'bridge_communities_test.dart' show CommunityHarness;
import 'community_chat_test.dart' show chatPage;

class _Fixture {
  _Fixture({bool holdAccount = false, String? error}) {
    host = scoped(() => CommunityHarness(
      capabilities: ['communities.chat', 'communities.chatDetail'],
      holdNames: {'communities.chat', if (holdAccount) 'account.getCurrent'},
      responses: {'communities.chat': chatPage()},
      error: error,
    ));
    attention = scoped(() => CommunityChatAttention(host.adapter));
    metrics.route('/profile');
  }
  int tick = 0;
  final rows = <Map<String, Object>>[];
  late final metrics = LoadingMetrics(nowUs: () => tick++, write: rows.add);
  late final CommunityHarness host;
  late final CommunityChatAttention attention;
  T scoped<T>(T Function() work) => runZoned(work,
      zoneValues: {loadingMetricsZoneKey: metrics});
  List<BridgeEnvelope> get chats => host.requests
      .where((request) => request.name == 'communities.chat').toList();
  Future<void> close() async {
    attention.dispose();
    await host.close();
    metrics.stop();
  }
}

void main() {
  testWidgets('unread bind keeps physical bridge work without blocking another page', (t) async {
    final f = _Fixture();
    addTearDown(f.close);
    f.scoped(() => f.attention.bind(['a' * 32]));
    await t.pump();
    expect(f.chats, hasLength(1));
    expect(f.metrics.pendingTransportsFor(1), 1);
    expect(f.metrics.pendingPageReadsFor(1), 0);
    await f.host.reply(f.chats.single);
    await t.pump();
    expect(f.attention.count('a' * 32), 2);
    expect(f.metrics.pendingTransportsFor(1), 0);
    expect(f.rows.where((row) => row['kind'] == 'transport' &&
        row['operation'] == 'communities.chat' && row['outcome'] == 'ok'), hasLength(1));
  });

  testWidgets('unread worker handoff remains passive after route change', (t) async {
    final f = _Fixture();
    addTearDown(f.close);
    f.scoped(() => f.attention.bind(['a' * 32, 'b' * 32, 'c' * 32, 'd' * 32]));
    await t.pump();
    expect(f.chats, hasLength(3));
    f.metrics.route('/rooms');
    await f.host.reply(f.chats.first);
    await t.pump();
    expect(f.chats, hasLength(4));
    expect(f.metrics.pendingTransportsFor(2), 1);
    expect(f.metrics.pendingPageReadsFor(2), 0);
    expect(f.host.requests.where((r) => r.name == 'bridge.cancel'), isEmpty);
    for (final request in f.chats.skip(1).toList()) {
      await f.host.reply(request);
    }
    await t.pump();
    expect(f.metrics.pendingTransportsFor(1), 0);
    expect(f.metrics.pendingTransportsFor(2), 0);
  });

  testWidgets('foreground shared account borrower still waits beside unread work', (t) async {
    final f = _Fixture(holdAccount: true);
    addTearDown(f.close);
    f.scoped(() => f.attention.bind(['a' * 32]));
    final read = f.scoped(() => f.metrics.foreground(
        () => f.host.adapter.readChat('a' * 32)));
    await t.pump();
    expect(f.metrics.pendingPageReadsFor(1), greaterThan(0));
    final accounts = f.host.requests.where((r) => r.name == 'account.getCurrent');
    expect(accounts, hasLength(1));
    expect(f.chats, isEmpty);
    await f.host.reply(accounts.single);
    await t.pump();
    expect(f.metrics.pendingPageReadsFor(1), greaterThan(0));
    // Shared account admission never grants the passive owner the right to
    // discard the foreground caller's independent consumer lease.
    for (final request in f.chats.toList()) {
      await f.host.reply(request);
    }
    await t.pump();
    expect((await read).targetRef, 'a' * 32);
    expect(f.metrics.pendingTransportsFor(1), 0);
    expect(f.metrics.pendingPageReadsFor(1), 0);
  });

  testWidgets('unread failure keeps real physical error statistics', (t) async {
    final f = _Fixture(error: 'communities.unavailable');
    addTearDown(f.close);
    f.scoped(() => f.attention.bind(['a' * 32]));
    await t.pump();
    expect(f.metrics.pendingPageReadsFor(1), 0);
    expect(f.metrics.pendingTransportsFor(1), 1);
    await f.host.reply(f.chats.single);
    await t.pump();
    expect(f.metrics.pendingTransportsFor(1), 0);
    expect(f.attention.readError('a' * 32), isNotNull);
    expect(f.rows.where((row) => row['kind'] == 'transport' &&
        row['operation'] == 'communities.chat' && row['outcome'] == 'error'), hasLength(1));
  });
}
