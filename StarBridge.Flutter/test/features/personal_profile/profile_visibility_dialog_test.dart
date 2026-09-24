import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_visibility.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_visibility_dialog.dart';

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

void main() {
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
      expect(find.byType(CheckboxListTile), findsNWidgets(4));
      expect(find.text('舰队、组织与好友可见'), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile-visibility-friendsOnly')));
      await tester.pump();
      expect(access.writes, 0);
      access.fail = true;
      await tester.tap(find.text('保存可见度'));
      await tester.pumpAndSettle();
      expect(find.text('暂时无法确认可见度。请刷新后查看当前设置。'), findsOneWidget);
      expect(access.state.visibility, PersonalProfileVisibility.onlyMe);
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      access.fail = false;
      access.pending = Completer<void>();
      await tester.tap(
        find.byKey(
          const Key('profile-visibility-friendsFleetAndOrganizations'),
        ),
      );
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
