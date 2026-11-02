import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/bridge_overlay_workspace_adapter.dart';
import 'package:starbridge_flutter/features/overlay_settings/host_unavailable_overlay_settings_adapter.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_settings_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

import '../../_support/overlay_loading_payload.dart';

// The module has no widget dependency. Control only its periodic clock while
// leaving real bridge futures and their request deadlines on the normal loop.
class _WatchTimer implements Timer {
  _WatchTimer(this.interval, this.callback);
  final Duration interval;
  final void Function(Timer) callback;
  bool _active = true;
  int _tick = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;
  void fire() {
    if (!_active) return;
    _tick++;
    callback(this);
  }
}

class _Fixture {
  _Fixture({this.holdRuntime = false}) {
    scoped(() {
      final pair = InMemoryBridgeConnection.createPair();
      connection = pair.host;
      session = BridgeClientSession(connection: pair.client, sessionGeneration: 4)
        ..acceptHostCapabilities(['overlay.workspace', 'overlay.runtime']);
      module = OverlaySettingsModule(HostUnavailableOverlaySettingsAdapter(),
          workspacePort: BridgeOverlayWorkspaceAdapter(session));
      subscription = connection.incoming.listen((request) {
        requests.add(request);
        if (request.name == 'overlay.runtime.getState' && !holdRuntime) {
          unawaited(reply(request));
        }
      });
    });
    metrics.route('/profile');
  }
  final bool holdRuntime;
  int tick = 0;
  final rows = <Map<String, Object>>[];
  late final metrics = LoadingMetrics(nowUs: () => tick++, write: rows.add);
  late final BridgeConnection connection;
  late final BridgeClientSession session;
  late final OverlaySettingsModule module;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  final releases = <void Function()>[];
  final timers = <_WatchTimer>[];
  List<BridgeEnvelope> get workspaces => requests
      .where((r) => r.name == 'overlay.getWorkspace').toList();
  List<BridgeEnvelope> get runtimes => requests
      .where((r) => r.name == 'overlay.runtime.getState').toList();
  T scoped<T>(T Function() work) => runZoned(work,
      zoneValues: {loadingMetricsZoneKey: metrics},
      zoneSpecification: ZoneSpecification(createPeriodicTimer:
          (self, parent, zone, duration, callback) {
        final timer = _WatchTimer(duration, callback);
        timers.add(timer);
        return timer;
      }));
  void watch() => releases.add(scoped(module.watch));
  Future<void> fireWatchTimer() async {
    expect(timers, hasLength(1), reason: 'One existing shared watch clock');
    expect(timers.single.interval, const Duration(seconds: 10));
    timers.single.fire();
    await Future<void>.delayed(Duration.zero);
  }
  Future<void> prime() async {
    // synchronize intentionally refuses the initial reading/busy projection.
    // Establish the existing real initialized workspace before observing it.
    final read = scoped(module.initialize);
    await Future<void>.delayed(Duration.zero);
    expect(workspaces, hasLength(1));
    await reply(workspaces.single);
    await Future<void>.delayed(Duration.zero);
    if (holdRuntime) {
      expect(runtimes, hasLength(1));
      await reply(runtimes.single);
      await Future<void>.delayed(Duration.zero);
    }
    await read.timeout(const Duration(seconds: 2));
    expect(module.workspace!.projection.value.available, true,
        reason: 'Fixture must decode the real complete workspace contract');
    expect(metrics.pendingTransportsFor(1), 0);
    requests.clear();
  }
  Future<void> reply(BridgeEnvelope request, {bool fail = false}) =>
      connection.send(BridgeEnvelope(
        protocolVersion: 1, messageType: 'response', name: request.name,
        correlationId: request.correlationId, sessionGeneration: 4,
        status: fail ? 'error' : 'ok',
        error: fail ? const BridgeErrorBody(code: 'fixture.read_failed',
            message: 'fixture', retryable: false) : null,
        payload: request.name == 'overlay.getWorkspace'
            ? loadingWorkspacePayload() : loadingRuntimePayload,
      ));
  void expectRecordedRead(int visit) {
    expect(workspaces, isNotEmpty);
    expect(rows.where((r) => r['kind'] == 'transportStart' &&
        r['operation'] == 'overlay.workspace'), isNotEmpty,
        reason: 'Missing recorder context must not fake a passive pass');
    expect(metrics.pendingTransportsFor(visit), greaterThan(0));
  }
  Future<void> close() async {
    for (final release in releases) { release(); }
    module.dispose();
    await session.close().timeout(const Duration(seconds: 2));
    await subscription.cancel().timeout(const Duration(seconds: 2));
    await connection.close().timeout(const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);
    metrics.stop();
  }
}

void main() {
  test('watch immediate real workspace read does not block profile', () async {
    final f = _Fixture();
    try {
      await f.prime();
      f.watch();
      await Future<void>.delayed(Duration.zero);
      f.expectRecordedRead(1);
      expect(f.metrics.pendingPageReadsFor(1), 0);
      await f.reply(f.workspaces.single);
      await Future<void>.delayed(Duration.zero);
      expect(f.module.workspace!.projection.value.available, true);
      expect(f.runtimes, hasLength(1));
      expect(f.metrics.pendingTransportsFor(1), 0);
    } finally { await f.close(); }
  });

  test('watch ten second renewal is passive after route change', () async {
    final f = _Fixture();
    try {
      await f.prime();
      f.watch();
      await Future<void>.delayed(Duration.zero);
      await f.reply(f.workspaces.single);
      await Future<void>.delayed(Duration.zero);
      expect(f.module.workspace!.projection.value.available, true);
      f.metrics.route('/settings/privacy');
      await f.fireWatchTimer();
      expect(f.workspaces, hasLength(2));
      f.expectRecordedRead(2);
      expect(f.metrics.pendingPageReadsFor(2), 0);
      await f.reply(f.workspaces.last);
      await Future<void>.delayed(Duration.zero);
    } finally { await f.close(); }
  });

  test('watch runtime state tail stays recorded without page lease', () async {
    final f = _Fixture(holdRuntime: true);
    try {
      await f.prime();
      f.watch();
      await Future<void>.delayed(Duration.zero);
      await f.reply(f.workspaces.single);
      await Future<void>.delayed(Duration.zero);
      expect(f.module.workspace!.projection.value.available, true);
      expect(f.runtimes, hasLength(1));
      f.expectRecordedRead(1);
      expect(f.metrics.pendingPageReadsFor(1), 0);
      await f.reply(f.runtimes.single);
      await Future<void>.delayed(Duration.zero);
      expect(f.metrics.pendingTransportsFor(1), 0);
    } finally { await f.close(); }
  });

  test('page initialize retains its own real foreground wait', () async {
    final f = _Fixture();
    try {
      final read = f.scoped(f.module.initialize);
      await Future<void>.delayed(Duration.zero);
      f.expectRecordedRead(1);
      expect(f.metrics.pendingPageReadsFor(1), greaterThan(0));
      await f.reply(f.workspaces.single);
      await read;
      expect(f.module.workspace!.projection.value.available, true);
      expect(f.metrics.pendingPageReadsFor(1), 0);
    } finally { await f.close(); }
  });

  test('direct manual synchronize remains conservative foreground', () async {
    final f = _Fixture();
    try {
      await f.prime();
      final read = f.scoped(f.module.synchronize);
      await Future<void>.delayed(Duration.zero);
      f.expectRecordedRead(1);
      expect(f.metrics.pendingPageReadsFor(1), greaterThan(0));
      await f.reply(f.workspaces.single);
      await read;
      expect(f.metrics.pendingPageReadsFor(1), 0);
    } finally { await f.close(); }
  });

  test('passive watch failure keeps physical error receipt', () async {
    final f = _Fixture();
    try {
      await f.prime();
      f.watch();
      await Future<void>.delayed(Duration.zero);
      f.expectRecordedRead(1);
      expect(f.metrics.pendingPageReadsFor(1), 0);
      await f.reply(f.workspaces.single, fail: true);
      await Future<void>.delayed(Duration.zero);
      expect(f.rows.where((r) => r['kind'] == 'transport' &&
          r['operation'] == 'overlay.workspace' && r['outcome'] == 'error'),
          hasLength(1));
      expect(f.module.workspace!.projection.value.available, true,
          reason: 'Existing initialized display survives silent read failure');
    } finally { await f.close(); }
  });

  test('shared watch does not overlap and last observer stops timer', () async {
    final f = _Fixture();
    try {
      await f.prime();
      f.watch(); f.watch();
      await Future<void>.delayed(Duration.zero);
      expect(f.workspaces, hasLength(1));
      f.releases.first();
      await f.reply(f.workspaces.single);
      await Future<void>.delayed(Duration.zero);
      await f.fireWatchTimer();
      expect(f.workspaces, hasLength(2));
      f.releases.last();
      await f.reply(f.workspaces.last);
      await Future<void>.delayed(Duration.zero);
      expect(f.timers.single.isActive, false); await f.fireWatchTimer();
      expect(f.workspaces, hasLength(2));
    } finally { await f.close(); }
  });

  test('a read held across an edit leaves the edit; renewal skips a pending save', () async {
    final f = _Fixture();
    try {
      await f.prime();
      f.watch();
      await Future<void>.delayed(Duration.zero);
      await f.reply(f.workspaces.single);
      await Future<void>.delayed(Duration.zero);
      final workspace = f.module.workspace!;
      expect(workspace.projection.value.available, true);
      await f.fireWatchTimer();
      expect(f.workspaces, hasLength(2));
      // Edited while the renewal read is held: the edit starts saving and the
      // late read must not replace it.
      workspace.updateSetting('showNotice', true);
      await Future<void>.delayed(Duration.zero);
      await f.reply(f.workspaces.last);
      await Future<void>.delayed(Duration.zero);
      expect(workspace.projection.value.settings!['showNotice'], true);
      expect(workspace.projection.value.dirty, true, reason: 'save unanswered');
      // The next renewal does not read over the pending save; a further edit
      // waits for it instead of starting a second write.
      await f.fireWatchTimer();
      expect(f.workspaces, hasLength(2));
      workspace.updateSetting('opacity', .7);
      await Future<void>.delayed(Duration.zero);
      expect(workspace.projection.value.settings!['showNotice'], true);
      expect(workspace.projection.value.settings!['opacity'], .7);
      expect(
        f.requests.where((r) => r.name == 'overlay.updateWorkspace'),
        hasLength(1),
      );
      expect(f.requests.every((r) => const ['overlay.getWorkspace',
          'overlay.runtime.getState', 'overlay.updateWorkspace']
          .contains(r.name)), true);
    } finally { await f.close(); }
  });
}
