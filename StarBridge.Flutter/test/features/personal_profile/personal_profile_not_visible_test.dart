// "Not public" is the server's settled answer, not a failed read: no "temporarily"
// and no retry button. A real read failure keeps both.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_read_status.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/interaction_batch3i_test.dart'
    show scopedApp;

Widget _view(String failureKey) => scopedApp(
  PersonalProfileUnavailableView(
    failureKey: failureKey,
    retrying: false,
    onRetry: () async => const PersonalProfileActionResult(PersonalProfileActionOutcome.completed),
  ),
  InteractionSuite.standard,
  light: false,
);

void main() {
  testWidgets('a page the viewer may not see offers no retry', (tester) async {
    await tester.pumpWidget(_view('profile.visitor.notVisible'));
    await tester.pump();
    expect(find.text('无法查看个人页面'), findsOneWidget);
    expect(find.textContaining('暂时'), findsNothing);
    expect(find.byKey(const Key('profile-retry')), findsNothing);
  });

  testWidgets('a failed read keeps its title and retry', (tester) async {
    await tester.pumpWidget(_view('profile.error.unavailable'));
    await tester.pump();
    expect(find.text('暂时无法读取个人页面'), findsOneWidget);
    expect(find.byKey(const Key('profile-retry')), findsOneWidget);
  });
}
