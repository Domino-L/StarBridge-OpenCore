import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rally.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_ships_adapter.dart';

const _source = 'officialFleet:7';

final class _Port implements OfficialFleetRallyPort {
  int reads = 0;
  Completer<void>? held;
  @override
  bool get available => true;
  @override
  Future<OfficialFleetRallySnapshot> read(
    String sourceRef, {
    required bool online,
  }) async {
    reads++;
    await held?.future;
    return const OfficialFleetRallySnapshot(onlineCount: 1, rally: null);
  }

  @override
  Future<OfficialFleetRallyEligibility> eligibility(String sourceRef) async =>
      const OfficialFleetRallyEligibility(
        canStart: false,
        onlineCount: 1,
        remainingThisHour: 0,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Port port;
  late DateTime now;
  late OfficialFleetRallyController controller;

  Future<void> advance(WidgetTester tester, Duration by) async {
    now = now.add(by);
    await tester.pump(by);
  }

  void setUpController() {
    port = _Port();
    now = DateTime.utc(2026, 11, 2, 12);
    controller = OfficialFleetRallyController(
      port,
      now: () => now,
      interval: const Duration(hours: 1),
    );
  }

  testWidgets('a push long after the last read reads at once', (tester) async {
    setUpController();
    controller.bind(_source);
    await tester.pump();
    expect(port.reads, 1);
    await advance(tester, OfficialFleetRallyController.wakeGap);
    controller.wake();
    await tester.pump();
    expect(port.reads, 2);
    controller.dispose();
  });

  testWidgets('a burst of pushes costs one read per gap', (tester) async {
    setUpController();
    controller.bind(_source);
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      controller.wake();
      await advance(tester, const Duration(milliseconds: 500));
    }
    expect(port.reads, 1, reason: 'Inside the gap');
    await advance(tester, const Duration(seconds: 3));
    expect(port.reads, 2, reason: 'Late pushes are not dropped');
    await advance(tester, const Duration(minutes: 1));
    expect(port.reads, 2, reason: 'Nothing keeps reading afterwards');
    controller.dispose();
  });

  testWidgets('a push during a read is read after it', (tester) async {
    setUpController();
    port.held = Completer<void>();
    controller.bind(_source);
    await tester.pump();
    controller.wake();
    port.held!.complete();
    port.held = null;
    await tester.pump();
    expect(port.reads, 1);
    await advance(tester, OfficialFleetRallyController.wakeGap);
    expect(port.reads, 2);
    controller.dispose();
  });

  testWidgets('no fleet, or a fleet left, reads nothing', (tester) async {
    setUpController();
    controller.wake();
    await tester.pump();
    expect(port.reads, 0);
    controller.bind(_source);
    await tester.pump();
    controller.wake();
    controller.bind(null);
    final reads = port.reads;
    await advance(tester, const Duration(minutes: 1));
    expect(port.reads, reads);
    controller.dispose();
  });

  testWidgets('dispose stops a waiting read', (tester) async {
    setUpController();
    controller.bind(_source);
    await tester.pump();
    controller.wake();
    final reads = port.reads;
    controller.dispose();
    await advance(tester, const Duration(minutes: 1));
    expect(port.reads, reads);
  });

  testWidgets('the fleet module passes its push on to the rally', (
    tester,
  ) async {
    setUpController();
    final module = createOfficialFleetModule(
      InMemoryOfficialFleetAdapter.forReview(signedIn: false),
      UnavailableOfficialFleetOverviewAdapter(),
      UnavailableOfficialFleetMembersAdapter(),
      UnavailableOfficialFleetShipsAdapter(),
      rally: controller,
    );
    controller.bind(_source);
    await tester.pump();
    await advance(tester, OfficialFleetRallyController.wakeGap);
    final reads = port.reads;
    module.communication.onWorkspaceActivity!();
    await tester.pump();
    expect(port.reads, reads + 1);
    module.dispose();
  });
}
