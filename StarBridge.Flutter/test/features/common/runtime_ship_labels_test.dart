import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_member_banner.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_page.dart';
import 'package:starbridge_flutter/features/common/runtime_name_labels.dart';

import '../communities/community_workspace_test.dart';
import '../communities/community_workspace_view_test.dart' show host;
import '../communities/community_image_test_support.dart';
import '../party_rooms/party_rooms_test.dart'
    show TestRoomsPort, ready, room, wire;

void main() {
  test(
    'optional name enrichment is bounded, immutable and backwards compatible',
    () {
      expect(parseRuntimeNameLabels(null), isEmpty);
      expect(parseRuntimeNameLabels('invalid'), isEmpty);
      final names = parseRuntimeNameLabels({
        'en': '  Public model  ',
        'zhHans': '',
        'zhHant': 1,
        'accountId': 'must-not-be-copied',
        'runtimeId': 'must-not-be-copied',
      });
      expect(names, {'en': 'Public model'});
      expect(() => names['en'] = 'changed', throwsUnsupportedError);
      expect(parseRuntimeNameLabels({'en': 'x' * 513}), isEmpty);
      expect(
        runtimeNameLabel('Original', {}, const Locale('zh', 'CN')),
        'Original',
      );
      expect(
        runtimeNameLabel('Original', names, const Locale('zh', 'TW')),
        'Public model',
      );
    },
  );
  const labels = {
    'en': 'F8C Lightning',
    'zhHans': 'F8C 闪电',
    'zhHant': 'F8C 閃電',
  };
  for (final entry in const [
    (Locale('zh', 'CN'), 'F8C 闪电'),
    (Locale('zh', 'TW'), 'F8C 閃電'),
    (Locale('en'), 'F8C Lightning'),
  ]) {
    testWidgets('room ship labels reach the real page ${entry.$1}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final data = room('a');
      final member = (data['members'] as List).single as Map;
      member.addAll(<String, Object>{
        'presenceText': '游戏中',
        'presenceKey': 'presence.inGame',
        'shipText': 'ANVL_Lightning_F8C',
        'shipLabels': labels,
      });
      final port = TestRoomsPort()
        ..result = ready(wire(current: 'a', rooms: [data]));
      final module = PartyRoomsModule(port);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            entry.$1,
          ),
          locale: entry.$1,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(body: PartyRoomsPage(module: module)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.$2), findsOneWidget);
      expect(find.text('ANVL_Lightning_F8C'), findsNothing);
      member['shipText'] = 'Unknown';
      port.result = ready(wire(current: 'a', rooms: [data]));
      await module.refresh();
      await tester.pumpAndSettle();
      expect(
        find.text(entry.$2),
        findsNothing,
        reason: 'Stale labels must not resurrect a cleared ship',
      );
      member['shipText'] = 'Uncatalogued future ship';
      member.remove('shipLabels');
      port.result = ready(wire(current: 'a', rooms: [data]));
      await module.refresh();
      await tester.pumpAndSettle();
      expect(
        find.text('Uncatalogued future ship'),
        findsOneWidget,
        reason:
            'Old Host or unknown catalog data retains the valid original name',
      );
      await tester.pumpWidget(const SizedBox());
      module.dispose();
    });
    testWidgets('organization ship labels reach the real banner ${entry.$1}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = WorkspaceTestPort();
      String? currentShip = 'ANVL_Lightning_F8C';
      addTearDown(port.changes.close);
      port.reader = (target, query, offset) async {
        final payload = workspacePayload(target: target, query: query);
        ((payload['members'] as List).single as Map).addAll(<String, Object?>{
          'ship': currentShip,
          'shipLabels': labels,
        });
        return CommunityWorkspace.parse(payload);
      };
      await tester.pumpWidget(host(port, entry.$1));
      await settleCommunityImages(tester);
      expect(
        tester
            .widget<CommunityMemberBanner>(find.byType(CommunityMemberBanner))
            .ship,
        entry.$2,
      );
      currentShip = null;
      await tester
          .state<CommunityWorkspaceViewState>(
            find.byType(CommunityWorkspaceView),
          )
          .model
          .load(silent: true);
      await settleCommunityImages(tester);
      expect(
        tester
            .widget<CommunityMemberBanner>(find.byType(CommunityMemberBanner))
            .ship,
        isNot(entry.$2),
        reason: 'A revoked field cannot reuse old labels',
      );
      port.changes.add(null);
      await tester.pump();
      expect(
        find.byType(CommunityMemberBanner),
        findsNothing,
        reason: 'Account invalidation must clear the old member and its labels',
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
}
