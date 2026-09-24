import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_editor.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_port.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

void main() {
  testWidgets('profile invalidation ends editing before a fresh account read', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final port = _InvalidatingProfilePort();
    await tester.pumpWidget(
      StarBridgeApp(
        composition: AppComposition.forTest(
          windowChrome: InMemoryWindowChrome(),
          accountPort: InMemoryAccountAdapter.forReview(
            AccountReviewState.signedIn,
          ),
          personalProfilePort: port,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-edit')));
    await tester.pumpAndSettle();
    expect(find.byType(PersonalProfileEditorPanel), findsOneWidget);

    port.invalidate();
    await tester.pumpAndSettle();

    expect(find.byType(PersonalProfileEditorPanel), findsNothing);
    expect(find.byKey(const Key('profile-edit')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final class _InvalidatingProfilePort implements PersonalProfilePort {
  final _delegate = InMemoryPersonalProfileAdapter.forReview(signedIn: true);
  final _events = StreamController<void>.broadcast();

  void invalidate() => _events.add(null);

  @override
  Stream<void> get invalidations => _events.stream;

  @override
  Future<PersonalProfileSnapshot> read() => _delegate.read();

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) =>
      _delegate.save(edit);

  @override
  Future<void> close() async {
    await _events.close();
    await _delegate.close();
  }
}
