import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_visibility.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_visibility_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';

import '../settings/local_privacy_page_test.dart' show app, viewport;

class Access implements ProfileVisibilityAccess {
  ProfileVisibilityState state = const ProfileVisibilityState(
    2,
    PersonalProfileVisibility.onlyMe,
  );
  int writes = 0;
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<ProfileVisibilityState> readVisibility() async => state;
  @override
  Future<ProfileVisibilityState> saveVisibility(
    ProfileVisibilityState expected,
    PersonalProfileVisibility scope,
  ) async {
    writes++;
    if (fail) throw StateError('unavailable');
    await pending?.future;
    return state = ProfileVisibilityState(expected.revision + 1, scope);
  }
}

Finder visibilityRow(String value) => find
    .ancestor(
      of: find.byKey(Key('profile-visibility-$value')),
      matching: find.byType(GestureDetector),
    )
    .first;

void main() {
  testWidgets(
    'SCM audience uses main fleet without expanding to organizations',
    (tester) async {
      viewport(tester, const Size(440, 700));
      final access = Access()
        ..state = const ProfileVisibilityState(
          7,
          PersonalProfileVisibility.onlyMe,
          availableVisibilities: [
            PersonalProfileVisibility.everyone,
            PersonalProfileVisibility.friendsAndMainFleet,
            PersonalProfileVisibility.friendsOnly,
            PersonalProfileVisibility.onlyMe,
          ],
        );
      await tester.pumpWidget(
        app(Scaffold(body: ProfileVisibilityDialog(access: access))),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('profile-visibility-friendsAndMainFleet')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const Key('profile-visibility-friendsFleetAndOrganizations'),
        ),
        findsNothing,
      );
      expect(find.byType(StarBridgeCheckboxTile), findsNWidgets(4));
      expect(
        tester
            .widgetList<StarBridgeCheckboxTile>(
              find.byType(StarBridgeCheckboxTile),
            )
            .where((row) => row.value)
            .single
            .label,
        '仅自己可见',
      );
      expect(access.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'four audiences, explicit save, failure refresh and no duplicate writes',
    (tester) async {
      viewport(tester, const Size(440, 700));
      final access = Access();
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('open'),
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => ProfileVisibilityDialog(access: access),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(StarBridgeCheckboxTile), findsNWidgets(4));
      expect(find.text('舰队、组织与好友可见'), findsOneWidget);
      await tester.tap(visibilityRow('friendsOnly'));
      await tester.pump();
      expect(access.writes, 0);
      access.fail = true;
      await tester.tap(find.text('保存可见度'));
      await tester.pumpAndSettle();
      expect(find.text('暂时无法确认可见度。请刷新后查看当前设置。'), findsOneWidget);
      expect(access.state.visibility, PersonalProfileVisibility.onlyMe);
      await tester.tap(find.byKey(const Key('profile-visibility-reload')));
      await tester.pumpAndSettle();
      access.fail = false;
      access.pending = Completer<void>();
      await tester.tap(visibilityRow('friendsFleetAndOrganizations'));
      await tester.pump();
      await tester.tap(find.text('保存可见度'));
      await tester.pump();
      await tester.tap(find.text('保存可见度'));
      expect(access.writes, 2);
      access.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        access.state.visibility,
        PersonalProfileVisibility.friendsFleetAndOrganizations,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
