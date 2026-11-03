import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_controller.dart';

import 'community_workspace_test.dart' show workspacePayload;

class _Port extends Fake implements CommunityWorkspacePort, CommunityShipsPort {
  int reads = 0;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  bool get shipsAvailable => true;
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    reads++;
    throw StateError('read failed');
  }
}

void main() {
  test(
    'a failed ship summary is not read again by the rebuild it causes',
    () async {
      final port = _Port();
      final model = CommunityWorkspaceController(port, 'a' * 32);
      addTearDown(model.dispose);
      // The workspace asks on every build, and failing notifies a rebuild.
      model.addListener(() {
        if (port.reads < 50) model.loadShipSummary('zh-CN');
      });
      model.loadShipSummary('zh-CN');
      await pumpEventQueue();
      expect(port.reads, 1);
      expect(model.shipSummaryFailed, isTrue);
    },
  );

  test('a refresh that worked earns the summary one more read', () async {
    final port = _Port();
    var failing = true;
    final model = CommunityWorkspaceController(
      port,
      'a' * 32,
      readWorkspace: (target, query, page, prepareMediaOnly) async {
        if (failing) throw const CommunityFailure('unavailable');
        return CommunityWorkspace.parse(workspacePayload());
      },
    );
    addTearDown(model.dispose);
    model.loadShipSummary('zh-CN');
    await pumpEventQueue();
    expect(model.shipSummaryFailed, isTrue);
    // A refresh that also fails leaves it failed, and nothing reads again.
    await model.load();
    model.loadShipSummary('zh-CN');
    await pumpEventQueue();
    expect(port.reads, 1);
    expect(model.shipSummaryFailed, isTrue);
    failing = false;
    await model.load();
    expect(model.shipSummaryFailed, isFalse);
    model.loadShipSummary('zh-CN');
    await pumpEventQueue();
    expect(port.reads, 2);
    expect(model.shipSummaryFailed, isTrue);
  });
}
