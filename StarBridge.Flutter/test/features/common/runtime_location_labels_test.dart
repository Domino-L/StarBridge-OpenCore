import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_page.dart';
import 'package:starbridge_flutter/features/communities/community_member_banner.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_view.dart';

import '../communities/community_image_test_support.dart';
import '../communities/community_workspace_test.dart';
import '../communities/community_workspace_view_test.dart' show host;
import '../party_rooms/party_rooms_test.dart'
    show TestRoomsPort, ready, room, wire;

void main() {
  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets('room arrival target reaches the real page $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final data = room('a');
      final member = Map<String, Object?>.from(
        (data['members'] as List).single as Map,
      );
      data['members'] = [member];
      member.addAll(<String, Object?>{
        'presenceKey': 'presence.inGame',
        'locationText': 'Previous Port',
        'arrivalPendingConfirmation': true,
        'arrivalTargetCode': 'Current Port',
        'arrivalTargetLabels': {'en': 'Current Port', 'zhHans': '本次到达港口'},
      });
      final port = TestRoomsPort()
        ..result = ready(wire(current: 'a', rooms: [data]));
      final module = PartyRoomsModule(port);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            locale,
          ),
          locale: locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(body: PartyRoomsPage(module: module)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          locale.languageCode == 'zh'
              ? '本次到达港口 · 地点待确认'
              : 'Current Port · Location pending confirmation',
        ),
        findsOneWidget,
      );
      expect(find.text('Previous Port'), findsNothing);
      member['arrivalTargetCode'] = null;
      port.result = ready(wire(current: 'a', rooms: [data]));
      await module.refresh();
      await tester.pumpAndSettle();
      expect(
        find.text(
          locale.languageCode == 'zh'
              ? '地点待确认'
              : 'Location pending confirmation',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Previous Port'), findsNothing);
      member['arrivalPendingConfirmation'] = false;
      member['locationText'] = '';
      port.result = ready(wire(current: 'a', rooms: [data]));
      await module.refresh();
      await tester.pumpAndSettle();
      expect(find.textContaining('本次到达港口'), findsNothing);
      expect(find.textContaining('Current Port'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      module.dispose();
    });
    testWidgets(
      'organization locations and arrival use authorized current target $locale',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 950);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final port = WorkspaceTestPort();
        addTearDown(port.changes.close);
        final row = <String, Object?>{
          'location': 'Previous Port',
          'locationLabels': {'en': 'Previous Port', 'zhHans': '上一港口'},
          'hasServerSession': true,
          'arrivalPendingConfirmation': false,
          'arrivalTargetCode': 'TARGET_CURRENT',
          'arrivalTargetLabels': {'en': 'Arrival Port', 'zhHans': '本次到达港口'},
        };
        port.reader = (target, query, offset) async {
          final payload = workspacePayload(target: target, query: query);
          ((payload['members'] as List).single as Map).addAll(row);
          return CommunityWorkspace.parse(payload);
        };
        await tester.pumpWidget(host(port, locale));
        await settleCommunityImages(tester);
        String location() => tester
            .widget<CommunityMemberBanner>(find.byType(CommunityMemberBanner))
            .location;
        Future<void> reload() async {
          await tester
              .state<CommunityWorkspaceViewState>(
                find.byType(CommunityWorkspaceView),
              )
              .model
              .load(silent: true);
          await settleCommunityImages(tester);
        }

        expect(
          location(),
          locale.languageCode == 'zh' ? '上一港口' : 'Previous Port',
        );
        row['arrivalPendingConfirmation'] = true;
        await reload();
        expect(
          location(),
          contains(locale.languageCode == 'zh' ? '本次到达港口' : 'Arrival Port'),
        );
        expect(
          location(),
          contains(locale.languageCode == 'zh' ? '待确认' : 'confirmation'),
        );
        expect(
          location(),
          isNot(
            contains(locale.languageCode == 'zh' ? '上一港口' : 'Previous Port'),
          ),
        );
        row['arrivalTargetCode'] = null;
        await reload();
        expect(
          location(),
          contains(locale.languageCode == 'zh' ? '待确认' : 'confirmation'),
        );
        expect(location(), isNot(contains('Port')));
        expect(location(), isNot(contains('港口')));
        row['location'] = null;
        row['arrivalTargetCode'] = 'TARGET_CURRENT';
        await reload();
        expect(location(), isNot(contains('Arrival Port')));
        expect(location(), isNot(contains('本次到达港口')));
        row['location'] = 'Unknown';
        row['arrivalPendingConfirmation'] = false;
        row['locationHiddenReason'] = 'lowConfidence';
        await reload();
        expect(
          location(),
          contains(locale.languageCode == 'zh' ? '低可信度' : 'Low-confidence'),
        );
        row['location'] = 'Arrival Port';
        row['locationLabels'] = row['arrivalTargetLabels'];
        row['locationHiddenReason'] = null;
        await reload();
        expect(
          location(),
          locale.languageCode == 'zh' ? '本次到达港口' : 'Arrival Port',
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
