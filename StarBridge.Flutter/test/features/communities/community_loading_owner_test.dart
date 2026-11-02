import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_activity.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_controller.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_port.dart';
import 'package:starbridge_flutter/features/communities/community_announcements_refresh.dart';
import 'package:starbridge_flutter/features/communities/community_visible_refresh.dart';
import '../../_support/loading_ownership_original/reference_community_activity.dart' as original_activity;
import '../../_support/loading_ownership_original/reference_community_announcements_refresh.dart' as original_announcements;
import '../../_support/loading_ownership_original/reference_community_visible_refresh.dart' as original_visible;
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

import 'community_announcements_controller_test.dart' as fixture;
import 'community_announcements_test.dart' show target;

const _original = bool.fromEnvironment('LOADING_COMMUNITY_ORIGINAL');

class _Meter {
  final rows = <Map<String, Object>>[];
  int time = 0;
  late final metrics = LoadingMetrics(nowUs: () => time++, write: rows.add);
  Map<Object, Object> get zone => {loadingMetricsZoneKey: metrics};
}

void _cleanVisible(WidgetTester tester, _Meter meter, Completer<void> held, {StreamController<void>? changes}) {
  addTearDown(() async {
    if (!held.isCompleted) held.complete();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    if (changes != null && !changes.isClosed) await changes.close();
    meter.metrics.stop();
  });
}

class _VisibleProbe extends StatefulWidget {
  const _VisibleProbe(this.meter, this.read, {this.changes});
  final _Meter meter;
  final Future<void> Function() read;
  final Stream<void>? changes;
  @override
  State<_VisibleProbe> createState() => _VisibleState.choose();
}

abstract class _VisibleState extends State<_VisibleProbe> {
  _VisibleState();
  factory _VisibleState.choose() => _original ? _OriginalVisible() : _CandidateVisible();
}

class _CandidateVisible extends _VisibleState with CommunityVisibleRefresh<_VisibleProbe> {
  @override
  void initState() => runZoned(super.initState, zoneValues: widget.meter.zone);
  @override
  void didChangeDependencies() => runZoned(super.didChangeDependencies, zoneValues: widget.meter.zone);
  @override
  Future<void> refreshVisibleCommunity() => widget.read();
  @override
  Stream<void>? get communityChanges => widget.changes;
  @override
  bool get communityEventsHealthy => widget.changes != null;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _OriginalVisible extends _VisibleState with original_visible.CommunityVisibleRefresh<_VisibleProbe> {
  @override
  void initState() => runZoned(super.initState, zoneValues: widget.meter.zone);
  @override
  void didChangeDependencies() => runZoned(super.didChangeDependencies, zoneValues: widget.meter.zone);
  @override
  Future<void> refreshVisibleCommunity() => widget.read();
  @override
  Stream<void>? get communityChanges => widget.changes;
  @override
  bool get communityEventsHealthy => widget.changes != null;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _MeasuredAnnouncements extends fixture.AnnouncementsFake {
  _MeasuredAnnouncements(this.meter);
  final _Meter meter;
  @override
  Future<CommunityAnnouncementsPage> readAnnouncements(String targetRef, {int offset = 0, int? expectedRevision}) {
    final future = super.readAnnouncements(targetRef, offset: offset, expectedRevision: expectedRevision);
    meter.metrics.observe('communities.read', future, transport: true);
    return future;
  }
}

class _AnnouncementsProbe extends StatefulWidget {
  const _AnnouncementsProbe(this.meter, this.model);
  final _Meter meter;
  final CommunityAnnouncementsController model;
  @override
  State<_AnnouncementsProbe> createState() => _AnnouncementsState.choose();
}

abstract class _AnnouncementsState extends State<_AnnouncementsProbe> {
  _AnnouncementsState();
  factory _AnnouncementsState.choose() => _original ? _OriginalAnnouncements() : _CandidateAnnouncements();
}

class _CandidateAnnouncements extends _AnnouncementsState with CommunityAnnouncementsRefresh<_AnnouncementsProbe> {
  @override
  void initState() => runZoned(super.initState, zoneValues: widget.meter.zone);
  @override
  CommunityAnnouncementsController get announcementModel => widget.model;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _OriginalAnnouncements extends _AnnouncementsState with original_announcements.CommunityAnnouncementsRefresh<_AnnouncementsProbe> {
  @override
  void initState() => runZoned(super.initState, zoneValues: widget.meter.zone);
  @override
  CommunityAnnouncementsController get announcementModel => widget.model;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('organization timer is passive while an explicit page read still waits', (t) async {
    final meter = _Meter();
    meter.metrics.route('/profile');
    final held = Completer<void>();
    _cleanVisible(t, meter, held);
    Future<void> read() {
      meter.metrics.observe('communities.read', held.future, transport: true);
      return held.future;
    }
    await t.pumpWidget(MaterialApp(home: _VisibleProbe(meter, read)));
    await t.pump(const Duration(seconds: 15));
    expect(meter.metrics.pendingTransportsFor(1), 1);
    expect(meter.metrics.pendingPageReadsFor(1), 0);
    meter.metrics.foreground(read);
    expect(meter.metrics.pendingPageReadsFor(1), 1);
    expect(meter.metrics.pendingTransportsFor(1), 2);
    held.complete();
    await t.pump();
    expect(meter.metrics.pendingPageReadsFor(1), 0);
    await t.pumpWidget(const SizedBox());
    meter.metrics.stop();
  });

  testWidgets('organization stream callback marks its own read instead of relying on publisher scope', (t) async {
    final meter = _Meter();
    meter.metrics.route('/profile');
    final held = Completer<void>();
    final changes = StreamController<void>.broadcast(sync: true);
    _cleanVisible(t, meter, held, changes: changes);
    Future<void> read() {
      meter.metrics.observe('communities.read', held.future, transport: true);
      return held.future;
    }
    await t.pumpWidget(MaterialApp(home: _VisibleProbe(meter, read, changes: changes.stream)));
    // Producer runs outside the recorder zone. Subscription callbacks have
    // their own registered zones; the automatic read entry must set intent.
    changes.add(null);
    await t.pump(const Duration(milliseconds: 120));
    expect(meter.metrics.pendingTransportsFor(1), 1);
    expect(meter.metrics.pendingPageReadsFor(1), 0);
    expect(meter.rows.singleWhere((r) => r['kind'] == 'transportStart')['activity'], 'background');
    held.complete();
    await t.pump();
    await t.pumpWidget(const SizedBox());
    await changes.close();
    meter.metrics.stop();
  });

  testWidgets('resume reconciliation is passive without changing visibility gates', (t) async {
    final meter = _Meter();
    meter.metrics.route('/profile');
    final held = Completer<void>();
    _cleanVisible(t, meter, held);
    Future<void> read() {
      meter.metrics.observe('communities.read', held.future, transport: true);
      return held.future;
    }
    await t.pumpWidget(MaterialApp(home: _VisibleProbe(meter, read)));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump(const Duration(seconds: 15));
    expect(meter.metrics.pendingTransportsFor(1), 0);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(meter.metrics.pendingTransportsFor(1), 1);
    expect(meter.metrics.pendingPageReadsFor(1), 0);
    held.complete();
    await t.pump();
    await t.pumpWidget(const SizedBox());
    meter.metrics.stop();
  });

  testWidgets('an explicit foreground borrower can override an automatic callback scope', (t) async {
    final meter = _Meter();
    meter.metrics.route('/profile');
    final held = Completer<void>();
    _cleanVisible(t, meter, held);
    Future<void> read() => meter.metrics.foreground(() {
      meter.metrics.observe('communities.read', held.future, transport: true);
      return held.future;
    });
    await t.pumpWidget(MaterialApp(home: _VisibleProbe(meter, read)));
    await t.pump(const Duration(seconds: 15));
    expect(meter.metrics.pendingTransportsFor(1), 1);
    expect(meter.metrics.pendingPageReadsFor(1), 1);
    expect(meter.rows.singleWhere((r) => r['kind'] == 'transportStart')['activity'], 'foreground');
    held.complete();
    await t.pump();
    expect(meter.metrics.pendingPageReadsFor(1), 0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('announcement automatic read is passive; later manual refresh still blocks', (t) async {
    final meter = _Meter();
    meter.metrics.route('/profile');
    final port = _MeasuredAnnouncements(meter);
    final held = port.heldRead = Completer<CommunityAnnouncementsPage>();
    final model = CommunityAnnouncementsController(port, target);
    addTearDown(() async {
      final pending = port.heldRead;
      if (pending != null && !pending.isCompleted) {
        pending.complete(CommunityAnnouncementsPage.parse(port.payload()));
      }
      await t.pump();
      await t.pumpWidget(const SizedBox());
      model.dispose();
      await port.changes.close();
      meter.metrics.stop();
    });
    await t.pumpWidget(MaterialApp(home: _AnnouncementsProbe(meter, model)));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(seconds: 2));
    }
    expect(port.reads, hasLength(1));
    expect(meter.metrics.pendingTransportsFor(1), 1);
    expect(meter.metrics.pendingPageReadsFor(1), 0);
    held.complete(CommunityAnnouncementsPage.parse(port.payload()));
    await t.pump();
    final manual = port.heldRead = Completer<CommunityAnnouncementsPage>();
    final refreshed = meter.metrics.foreground(model.refresh);
    expect(meter.metrics.pendingPageReadsFor(1), 1);
    manual.complete(CommunityAnnouncementsPage.parse(port.payload()));
    await refreshed;
    await t.pump();
    expect(meter.metrics.pendingTransportsFor(1), 0);
    await t.pumpWidget(const SizedBox());
    meter.metrics.stop();
  });

  testWidgets('real community wait remains a physical request without blocking unrelated page', (t) async {
    final meter = _Meter();
    meter.metrics.route('/profile');
    final pair = InMemoryBridgeConnection.createPair();
    final session = BridgeClientSession(connection: pair.client, sessionGeneration: 1);
    session.acceptHostCapabilities(['communities.wait']);
    const owner = BridgeAccountContext(environment: 'fixture', authority: 'starbridge-relay-test', subject: 'fixture');
    final waits = <BridgeEnvelope>[];
    final host = pair.host.incoming.listen((request) {
      if (request.name == 'account.getCurrent') {
        unawaited(pair.host.send(BridgeEnvelope(
          protocolVersion: 1, messageType: 'response', name: request.name,
          correlationId: request.correlationId, sessionGeneration: 1,
          accountContext: owner, status: 'ok',
          payload: const {'schemaVersion': 1, 'state': 'legacySignedIn'},
        )));
      } else if (request.name == 'communities.wait') {
        waits.add(request);
      }
    });
    final dynamic source = runZoned(() => _original
      ? original_activity.CommunityActivity(session)
      : CommunityActivity(session), zoneValues: meter.zone);
    final subscription = runZoned(() =>
      (source.changes as StreamController<void>).stream.listen((_) {}), zoneValues: meter.zone);
    var closed = false;
    Future<void> close() async {
      if (closed) return;
      closed = true;
      await t.runAsync(() async {
        await subscription.cancel();
        await source.close();
        await host.cancel();
        await session.close();
        await pair.host.close();
      });
      meter.metrics.stop();
    }
    addTearDown(close);
    await t.pump(const Duration(milliseconds: 1));
    await t.pump();
    expect(waits, hasLength(1));
    expect(meter.metrics.pendingTransportsFor(1), 1);
    expect(meter.metrics.pendingPageReadsFor(1), 0);
    expect(meter.rows.where((r) => r['kind'] == 'transportStart').every((r) => r['activity'] == 'background'), isTrue);
    await close();
    await t.pump();
  });
}
