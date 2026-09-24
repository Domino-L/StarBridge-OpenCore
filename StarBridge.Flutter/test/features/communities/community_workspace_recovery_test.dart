import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';

import 'community_workspace_test.dart' show WorkspaceTestPort, workspacePayload;
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final code in ['refreshRequired', 'notAllowed', 'identityUnavailable']) {
    testWidgets(
      'automatic recovery is bounded and never retries $code authority failures',
      (tester) async {
        final port = WorkspaceTestPort();
        addTearDown(port.changes.close);
        port.reader = (_, _, _) async => throw CommunityFailure(code);
        var renewals = 0;
        var target = 'a' * 32;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) => host(
              port,
              const Locale('zh', 'CN'),
              target: target,
              organizationKey: 'stable-test-organization',
              onGovernanceChanged: () async {
                renewals++;
                setState(
                  () => target = renewals.toRadixString(16).padLeft(32, '0'),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        expect(renewals, code == 'refreshRequired' ? 1 : 0);
        expect(
          find.byKey(const Key('community-internal-workspace')),
          findsNothing,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'expired image request reauthorizes the workspace without replaying a command',
    (tester) async {
      final port = WorkspaceTestPort();
      addTearDown(port.changes.close);
      port.reader = (reference, _, _) async => CommunityWorkspace.parse(
        workspacePayload(target: reference)
          ..['hasLogo'] = reference == 'a' * 32,
      );
      port.mediaReader = (_, _) async =>
          throw const CommunityFailure('refreshRequired');
      var renewals = 0;
      var target = 'a' * 32;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => host(
            port,
            const Locale('zh', 'CN'),
            target: target,
            organizationKey: 'stable-test-organization',
            onGovernanceChanged: () async {
              renewals++;
              setState(() => target = 'c' * 32);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(renewals, 1);
      expect(
        find.byKey(const Key('community-internal-workspace')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'expired workspace reference renews membership once instead of stranding the page',
    (tester) async {
      final port = WorkspaceTestPort();
      addTearDown(port.changes.close);
      port.reader = (reference, query, offset) async {
        if (reference == 'a' * 32) {
          throw const CommunityFailure('refreshRequired');
        }
        return CommunityWorkspace.parse(workspacePayload(target: reference));
      };
      var renewals = 0;
      var target = 'a' * 32;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => host(
            port,
            const Locale('zh', 'CN'),
            target: target,
            organizationKey: 'stable-test-organization',
            onGovernanceChanged: () async {
              renewals++;
              setState(() => target = 'c' * 32);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(renewals, 1);
      expect(
        find.byKey(const Key('community-internal-workspace')),
        findsOneWidget,
      );
      expect(find.text('资料已过期，请刷新组织后重试。'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
