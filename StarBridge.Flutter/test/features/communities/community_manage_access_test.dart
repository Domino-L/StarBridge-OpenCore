// User 2026-10-31: the outer entry stays for everyone, who have their own
// settings inside; sections they cannot use do not show. This replaces the
// 2026-10-29 rule that no grant meant no entry. Earlier report:
// "我明明没有任何权限，但是为什么可以访问管理".
// Creating invites is open to every member under the common policy; that
// alone must not open the management tab.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_holo_workspace.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';

import 'community_image_test_support.dart';
import 'community_workspace_test.dart';

CommunityWorkspace _workspace(Map<String, bool> access) {
  final payload = workspacePayload();
  (payload['access'] as Map).addAll(access);
  return CommunityWorkspace.parse(payload);
}

void main() {
  test('invites alone are not a management grant', () {
    final inviteOnly = _workspace({'canCreateInvite': true});
    expect(communityCanManage(inviteOnly), isFalse);
    expect(communityCanOnlyInvite(inviteOnly), isTrue);
    for (final grant in [
      'isOwner',
      'canEditProfile',
      'canReviewApplications',
      'canRemoveMembers',
      'canManageAnnouncements',
    ]) {
      final managed = _workspace({grant: true, 'canCreateInvite': true});
      expect(communityCanManage(managed), isTrue, reason: grant);
      expect(communityCanOnlyInvite(managed), isFalse, reason: grant);
    }
    expect(communityCanManage(_workspace({})), isFalse);
    expect(communityCanOnlyInvite(_workspace({})), isFalse);
  });

  for (final (access, manage) in [
    (const <String, bool>{}, false),
    (const {'canCreateInvite': true}, false),
    (const {'canManageAnnouncements': true}, true),
  ]) {
    testWidgets('management inside follows real grants $access', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = WorkspaceTestPort();
      addTearDown(port.changes.close);
      port.reader = (target, query, _) async {
        final payload = workspacePayload(target: target, query: query);
        (payload['access'] as Map).addAll(access);
        return CommunityWorkspace.parse(payload);
      };
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            const Locale('zh', 'CN'),
          ),
          home: Scaffold(
            body: CommunityWorkspaceView(
              port: port,
              targetRef: 'a' * 32,
              organizationKey: 'org',
              holo: true,
              actions: const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await settleCommunityImages(tester);
      await tester.pumpAndSettle();
      // The page opens for everyone; only a real grant shows management.
      await tester.tap(
        find.byKey(const Key('official-fleet-tab-manage')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('community-internal-workspace')),
        findsOneWidget,
      );
      expect(find.text('常用管理'), manage ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
