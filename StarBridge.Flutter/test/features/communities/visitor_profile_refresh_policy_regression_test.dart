import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/user_interaction.dart';
import 'package:starbridge_flutter/features/common/user_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_avatar.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';

import 'community_visitor_profile_test.dart' show VisitorPort;
import '../friends/social_layout_test.dart' show app, loadFonts;

void main() {
  setUpAll(loadFonts);
  for (final throwsTimeout in [false, true]) {
    testWidgets(
      'visitor refresh cannot restore withdrawn content after ${throwsTimeout ? 'a timeout' : 'a marked transient failure'}',
      (tester) async {
        final port = VisitorPort();
        addTearDown(port.changes.close);
        await tester.pumpWidget(
          app(
            UserProfilePage(
              port: port,
              target: UserTarget.community('a' * 32, 'b' * 32),
              avatarImageData: 'entry-avatar',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Authorized shared introduction'), findsOneWidget);
        expect(find.byType(PersonalProfileAvatar), findsOneWidget);

        port.pending = Completer<PersonalProfileSnapshot>();
        await tester.tap(find.byKey(const Key('visitor-profile-refresh')));
        await tester.pump();
        expect(find.text('Authorized shared introduction'), findsNothing);
        expect(find.byType(PersonalProfileAvatar), findsNothing);
        if (throwsTimeout) {
          port.pending!.completeError(TimeoutException('Synthetic timeout'));
        } else {
          port.pending!.complete(
            const PersonalProfileSnapshot.unavailable(
              failureKey: 'profile.error.hostUnavailable',
              transientReadFailure: true,
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(find.text('Authorized shared introduction'), findsNothing);
        expect(find.text('Visitor Pilot'), findsNothing);
        expect(find.byType(PersonalProfileAvatar), findsNothing);

        port.pending = null;
        await tester.tap(find.byKey(const Key('visitor-profile-refresh')));
        await tester.pumpAndSettle();
        expect(find.text('Authorized shared introduction'), findsOneWidget);
        expect(port.reads, 3);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
