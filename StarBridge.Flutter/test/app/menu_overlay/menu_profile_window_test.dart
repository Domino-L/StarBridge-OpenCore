import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/menu_profile_page.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profile_view.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts;
import 'menu_profiles_session_test.dart' show fixtureProfile;

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'existing visitor page fits a resized tool and clears on revocation',
    (tester) async {
      var refreshes = 0;
      final ready = MenuProfileView.parse(
        MenuProfileView.encode(fixtureProfile),
      );
      for (final width in [900.0, 560.0, 360.0]) {
        size(tester, Size(width, 500));
        await tester.pumpWidget(
          app(MenuProfileWindowPage(view: ready, onRefresh: () => refreshes++)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Synthetic profile'), findsOneWidget);
        expect(find.text('编辑个人页面'), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text('刷新个人页面'));
      await tester.pump();
      expect(refreshes, 1);
      await tester.pumpWidget(
        app(
          MenuProfileWindowPage(
            view: const MenuProfileView('loading'),
            onRefresh: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Synthetic profile'), findsOneWidget);
      await tester.pumpWidget(
        app(
          MenuProfileWindowPage(
            view: const MenuProfileView('revoked'),
            onRefresh: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic profile'), findsNothing);
      expect(find.text('成员资料已更新。请返回并刷新列表后重试。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
