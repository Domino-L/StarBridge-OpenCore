import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_header.dart';

import 'community_ships_test.dart' show shipRow;
import 'community_workspace_test.dart' show WorkspaceTestPort;
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

class ExpiringShipsPort extends WorkspaceTestPort
    implements CommunityShipsPort {
  bool expired = false;
  final reads = <String>[];
  @override
  bool get shipsAvailable => true;
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    reads.add(targetRef);
    if (expired && targetRef == 'a' * 32) {
      throw const CommunityFailure('refreshRequired');
    }
    return CommunityShipsPage.parse({
      'schemaVersion': 1,
      'queryVersion': 2,
      'query': query!.toPayload(),
      'targetRef': targetRef,
      'revision': 'b' * 64,
      'offset': offset,
      'totalCount': 1,
      'matchedCount': 1,
      'next': null,
      'ships': [shipRow()..['ownerHasAvatar'] = false],
    });
  }
}

void main() {
  setUpAll(loadFonts);
  for (final fromShips in [false, true]) {
    testWidgets(
      'expired workspace refresh reacquires membership and keeps ships open (ships=$fromShips)',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final port = ExpiringShipsPort();
        addTearDown(port.changes.close);
        var membershipReads = 0;
        final refreshFinished = Completer<void>();
        await tester.pumpWidget(
          host(
            port,
            const Locale('zh', 'CN'),
            organizationKey: 'org-a',
            onGovernanceChanged: () async {
              membershipReads++;
              await refreshFinished.future;
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('community-section-ships')));
        await tester.pumpAndSettle();
        port.expired = true;
        // The next visible refresh after a >5 minute background interval receives
        // the real Host's refreshRequired result; no wall-clock sleep or network.
        await tester.pump(const Duration(seconds: 16));
        await tester.pumpAndSettle();
        expect(port.reads.length, greaterThan(1));
        final oldReadCount = port.reads.length;
        final headerRefresh = find.descendant(
          of: fromShips
              ? find.byType(CommunityShipsPanel)
              : find.byType(CommunityWorkspaceHeader),
          matching: find.byIcon(Icons.refresh),
        );
        await tester.tap(headerRefresh);
        await tester.pumpAndSettle();
        expect(
          membershipReads,
          1,
          reason: 'Refresh must acquire a fresh membership reference, not reuse the expired one.',
        );
        await tester.tap(headerRefresh);
        await tester.pumpAndSettle();
        expect(
          membershipReads,
          1,
          reason: 'Overlapping refreshes are coalesced.',
        );
        await tester.pumpWidget(
          host(
            port,
            const Locale('zh', 'CN'),
            target: 'c' * 32,
            organizationKey: 'org-a',
            onGovernanceChanged: () async {
              membershipReads++;
            },
          ),
        );
        refreshFinished.complete();
        await tester.pumpAndSettle();
        expect(find.byType(CommunityShipsPanel), findsOneWidget);
        expect(port.reads.skip(oldReadCount), isNotEmpty);
        expect(port.reads.skip(oldReadCount), everyElement('c' * 32));
        await tester.pumpWidget(
          host(
            port,
            const Locale('zh', 'CN'),
            target: 'd' * 32,
            organizationKey: 'org-b',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(CommunityShipsPanel),
          findsNothing,
          reason: 'Do not retain ships on a different organization.',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final error in [
    'refreshRequired',
    'notAllowed',
    'identityUnavailable',
  ]) {
    testWidgets('workspace recovery action respects $error', (tester) async {
      final port = WorkspaceTestPort();
      addTearDown(port.changes.close);
      port.reader = (_, _, _) async => throw CommunityFailure(error);
      var reads = 0;
      await tester.pumpWidget(
        host(
          port,
          const Locale('zh', 'CN'),
          onGovernanceChanged: () async {
            reads++;
          },
        ),
      );
      await tester.pumpAndSettle();
      if (error == 'refreshRequired') {
        expect(
          reads,
          1,
          reason:
              'One automatic reauthorization attempt precedes manual recovery.',
        );
        await tester.tap(find.byType(TextButton));
        await tester.pumpAndSettle();
        expect(reads, 2);
        await tester.pump(const Duration(minutes: 6));
        expect(
          reads,
          2,
          reason: 'No automatic retry loop after recovery fails.',
        );
      } else {
        expect(find.byType(TextButton), findsNothing);
        expect(reads, 0);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
