import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';

import 'community_workspace_test.dart' show WorkspaceTestPort, workspacePayload;
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

// User report 2026-10-23: while the Japan relay restarted (502 for ~20 s) the
// organization page stayed on "更新未完成，请重试" until a manual retry. A
// transient failure now re-reads by itself once the connection is back.
void main() {
  setUpAll(loadFonts);
  testWidgets('a transient failure re-reads by itself after the outage', (
    tester,
  ) async {
    final port = WorkspaceTestPort();
    addTearDown(port.changes.close);
    var reads = 0;
    port.reader = (reference, query, _) async {
      reads++;
      if (reads <= 2) throw const CommunityFailure('unavailable');
      return CommunityWorkspace.parse(
        workspacePayload(target: reference, query: query),
      );
    };
    await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.byKey(const Key('community-internal-workspace')), findsNothing);
    // Fixed steps: pumpAndSettle would run the loading animation forward and
    // fire later retries early.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(reads, 2, reason: 'No automatic re-read after a transient failure.');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(reads, 3);
    expect(
      find.byKey(const Key('community-internal-workspace')),
      findsOneWidget,
    );
    // Recovered: no failure notice. (The page's ordinary periodic refresh
    // continues as before; it is not part of this recovery.)
    expect(
      find.byKey(const Key('community-workspace-refresh-error')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving the page stops the recovery', (tester) async {
    final port = WorkspaceTestPort();
    addTearDown(port.changes.close);
    var reads = 0;
    port.reader = (_, _, _) async {
      reads++;
      throw const CommunityFailure('unavailable');
    };
    await tester.pumpWidget(host(port, const Locale('zh', 'CN')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 60));
    expect(reads, 1);
  });
}
