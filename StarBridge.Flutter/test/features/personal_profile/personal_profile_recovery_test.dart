import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_port.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

void main() {
  test(
    'manual refresh is single flight while invalidation still queues a read',
    () async {
      final port = _RecoveryPort();
      final module = createPersonalProfileModule(port);
      addTearDown(module.dispose);
      await module.initialize();
      port.pending = Completer<PersonalProfileSnapshot>();
      final first = module.refresh();
      expect(
        (await module.refresh()).outcome,
        PersonalProfileActionOutcome.rejected,
      );
      expect(port.readCount, 2);
      port.pending!.complete(await port.delegate.read());
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(port.readCount, 2);

      port.pending = Completer<PersonalProfileSnapshot>();
      final second = module.refresh();
      port.events.add(null);
      final pending = port.pending!;
      port.pending = null;
      pending.complete(await port.delegate.read());
      await second;
      await Future<void>.delayed(Duration.zero);
      expect(port.readCount, 4);
      expect(
        module.projection.value.availability,
        PersonalProfileAvailability.available,
      );
    },
  );

  testWidgets('owner can refresh a loaded profile without editing it', (
    tester,
  ) async {
    final port = _RecoveryPort();
    await _openProfile(tester, port);
    final baselineReads = port.readCount;
    final refresh = find.byKey(const Key('profile-refresh'));
    expect(refresh, findsOneWidget);
    await tester.ensureVisible(refresh);
    port.pending = Completer<PersonalProfileSnapshot>();
    await tester.tap(refresh);
    await tester.pump();
    expect(port.readCount, baselineReads + 1);
    expect(find.text('正在读取个人页面…'), findsOneWidget);
    expect(port.saveCount, 0);
    port.pending!.complete(await port.delegate.read());
    await tester.pumpAndSettle();
    expect(refresh, findsOneWidget);
    expect(find.byKey(const Key('profile-identity-header')), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile-edit')));
    await tester.pumpAndSettle();
    expect(refresh, findsNothing);
    expect(port.saveCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'profile retry keeps its failure and busy feedback until recovered',
    (tester) async {
      final port = _RecoveryPort(unavailable: true);
      await _openProfile(tester, port);
      final baselineReads = port.readCount;
      port.pending = Completer<PersonalProfileSnapshot>();
      await tester.tap(find.byKey(const Key('profile-retry')));
      await tester.pump();
      expect(find.byKey(const Key('profile-unavailable')), findsOneWidget);
      expect(find.text('暂时无法读取个人页面'), findsOneWidget);
      expect(find.text('正在重试…'), findsOneWidget);
      final retry = find.byKey(const Key('profile-retry'));
      expect(tester.widget<OutlinedButton>(retry).onPressed, isNull);
      expect(
        find.descendant(
          of: retry,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      await tester.tap(retry);
      await tester.pump();
      expect(port.readCount, baselineReads + 1);
      port.pending!.complete(await port.delegate.read());
      await tester.pumpAndSettle();
      expect(port.readCount, baselineReads + 1);
      expect(find.byKey(const Key('profile-unavailable')), findsNothing);
      expect(find.byKey(const Key('profile-identity-header')), findsOneWidget);
      expect(port.saveCount, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _openProfile(WidgetTester tester, _RecoveryPort port) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 1000);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
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
}

final class _RecoveryPort implements PersonalProfilePort {
  _RecoveryPort({this.unavailable = false});
  final bool unavailable;
  final delegate = InMemoryPersonalProfileAdapter.forReview(signedIn: true);
  final events = StreamController<void>.broadcast(sync: true);
  Completer<PersonalProfileSnapshot>? pending;
  int readCount = 0;
  int saveCount = 0;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<PersonalProfileSnapshot> read() {
    readCount++;
    return pending?.future ??
        (unavailable
            ? Future.value(
                const PersonalProfileSnapshot.unavailable(
                  failureKey: 'profile.error.unavailable',
                ),
              )
            : delegate.read());
  }

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) {
    saveCount++;
    return delegate.save(edit);
  }

  @override
  Future<void> close() async {
    await events.close();
    await delegate.close();
  }
}
