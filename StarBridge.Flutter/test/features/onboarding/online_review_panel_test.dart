import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_review_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_controller.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_port.dart';

import 'onboarding_page_test.dart' show pumpSetup;
import 'onboarding_test_support.dart';
import 'online_review_test_support.dart';
import 'retained_online_review_test.dart' show retainedWire, retainedReview;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final font in <String, String>{
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Saira': 'assets/fonts/Saira-VF.ttf',
      'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
      // Headless tests have no system fonts. Use a bundled CJK face for
      // the Traditional Chinese fallback family without changing product fonts.
      'Microsoft JhengHei UI': 'assets/fonts/SourceHanSansCN-VF.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    for (final state in ['verificationRequired', 'mismatch']) {
      testWidgets(
        'merged account $state at 320 width and 160 percent: $locale',
        (tester) async {
          tester.view.physicalSize = const Size(320, 840);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final port = FakeOnlinePort()
            ..snapshot = OnlineReviewWire.parse(
              onlineWire(
                state: state,
                local: 'Pilot-Example',
                remote: state == 'mismatch' ? 'Other-Pilot' : null,
                display: 'Synthetic Pilot',
              ),
            );
          final online = OnlineReviewController(port);
          addTearDown(online.dispose);
          addTearDown(port.close);
          final mainPort = FakeOnboardingPort(
            facts(confirmed: true, onlineSetupPending: true, matched: false),
          );
          await pumpSetup(
            tester,
            step: OnboardingStep.mode,
            mode: OnboardingMode.online,
            port: mainPort,
            onlineReview: online,
            locale: locale,
            scale: 1.6,
          );
          final copy = OnboardingCopy(locale);
          expect(find.text(copy.text('onlineReview.title')), findsNothing);
          expect(find.text(copy.text('accountCard.title')), findsOneWidget);
          if (state == 'mismatch') {
            expect(find.text('Pilot-Example'), findsOneWidget);
            expect(find.text('Other-Pilot'), findsOneWidget);
            expect(
              find.text(copy.text('onlineReview.localHandle')),
              findsOneWidget,
            );
            expect(
              find.text(copy.text('onlineReview.scmHandle')),
              findsOneWidget,
            );
            expect(
              find.text(copy.text('onlineReview.confirmOne')),
              findsNothing,
            );
          } else {
            expect(
              find.text(copy.text('accountCard.unverified')),
              findsOneWidget,
            );
            expect(
              find.text(copy.text('onlineReview.localHandle')),
              findsNothing,
            );
            expect(
              find.text(copy.text('onlineReview.scmHandle')),
              findsNothing,
            );
          }
          for (final key in [
            'online-account-change',
            'online-review-cancel',
            'online-review-refresh',
          ]) {
            final button = find.byKey(Key(key));
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            expect(button.hitTestable(), findsOneWidget);
          }
          // Old-account data migrates only to the SCM account it was linked to.
          expect(
            find.text(copy.text('accountCard.migrationHint')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('online-review-confirm')), findsNothing);
          expect(mainPort.actions, isEmpty);
          expect(mainPort.finishes, 0);
          expect(mainPort.saves, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
    testWidgets(
      'retained resume has truthful labels and cancellable waiting: $locale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 840);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = FakeOnlinePort()
          ..snapshot = OnlineReviewWire.parse(
            retainedWire(),
            retainedProtocol: true,
          );
        final online = OnlineReviewController(port);
        addTearDown(online.dispose);
        addTearDown(port.close);
        final resume = Completer<OnlineReviewSnapshot>(),
            cancel = Completer<OnlineReviewSnapshot>();
        port.onAction = (action) =>
            action == OnlineReviewAction.resume ? resume.future : cancel.future;
        await pumpSetup(
          tester,
          step: OnboardingStep.mode,
          mode: OnboardingMode.online,
          observation: facts(confirmed: true, onlineSetupPending: true),
          onlineReview: online,
          locale: locale,
          scale: 1.6,
        );
        final copy = OnboardingCopy(locale);
        expect(port.actions, isEmpty);
        expect(find.text(copy.text('onlineReview.resume')), findsOneWidget);
        expect(find.text(copy.text('login')), findsNothing);
        final button = find.byKey(const Key('online-review-login'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        expect(port.actions, [OnlineReviewAction.resume]);
        expect(find.text(copy.text('onlineReview.restoring')), findsOneWidget);
        expect(find.text(copy.text('onlineReview.authorizing')), findsNothing);
        final stop = find.byKey(const Key('online-review-cancel'));
        expect(
          find.text(copy.text('onlineReview.cancelResume')),
          findsOneWidget,
        );
        await tester.ensureVisible(stop);
        await tester.tap(stop);
        await tester.pump();
        expect(online.value.action, OnlineReviewAction.cancel);
        expect(
          find.text(copy.text('onlineReview.cancellingResume')),
          findsOneWidget,
        );
        resume.complete(
          OnlineReviewWire.parse(retainedReview(), retainedProtocol: true),
        );
        await tester.pump();
        expect(online.value.busy, true);
        cancel.complete(
          OnlineReviewWire.parse(
            retainedWire(mode: 'offline', state: 'notStarted', revision: 8),
            retainedProtocol: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(online.value.snapshot.modeState, OnlineReviewModeState.offline);
        expect(online.value.canConfirm, false);
        expect(tester.takeException(), null);
      },
    );
    testWidgets(
      'Handle review remains explicit at 320 width / 160% text: $locale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 840);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = FakeOnlinePort()
          ..snapshot = OnlineReviewWire.parse(reviewWire());
        final online = OnlineReviewController(port);
        addTearDown(online.dispose);
        addTearDown(port.close);
        final mainPort = FakeOnboardingPort(
          facts(
            confirmed: true,
            matched: false,
            onlineReviewed: false,
            onlineSetupPending: true,
          ),
        );
        port.onAction = (action) async {
          expect(action, OnlineReviewAction.confirm);
          mainPort.facts = facts(
            confirmed: true,
            onlineReviewed: false,
            onlineSetupPending: true,
          );
          return port.snapshot = OnlineReviewWire.parse(
            reviewWire(confirmed: true),
          );
        };
        await pumpSetup(
          tester,
          step: OnboardingStep.mode,
          mode: OnboardingMode.online,
          port: mainPort,
          onlineReview: online,
          locale: locale,
          scale: 1.6,
        );
        expect(port.actions, isEmpty);
        expect(online.value.canConfirm, true);
        expect(find.text('PILOT-EXAMPLE'), findsOneWidget);
        final copy = OnboardingCopy(locale);
        expect(find.text(copy.text('retry')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('onboarding-next')),
            matching: find.text(copy.text('next')),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('onboarding-next')))
              .onPressed,
          null,
        );
        final confirm = find.byKey(const Key('online-review-confirm'));
        for (final name in ['PILOT-EXAMPLE']) {
          for (final element in find.text(name).evaluate().toList()) {
            final target = find.byWidget(element.widget);
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            expect(target.hitTestable(), findsOneWidget);
          }
        }
        final match = find.text(copy.text('onlineReview.namesMatch'));
        await tester.ensureVisible(match);
        await tester.pumpAndSettle();
        expect(match.hitTestable(), findsOneWidget);
        await tester.ensureVisible(confirm);
        await tester.pumpAndSettle();
        expect(confirm.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        final visual = Platform.environment['STARBRIDGE_TEST_VISUAL_DIR'];
        if (visual != null) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('onboarding-capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!;
              await Directory(visual).create(recursive: true);
              await File('$visual/r2-review-320-$locale.png').writeAsBytes(
                bytes.buffer.asUint8List(
                  bytes.offsetInBytes,
                  bytes.lengthInBytes,
                ),
              );
            } finally {
              image.dispose();
            }
          });
        }
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(port.actions, [OnlineReviewAction.confirm]);
        expect(mainPort.finishes, 0);
        expect(mainPort.saves, 0);
        expect(mainPort.actions, isEmpty);
        expect(online.value.snapshot.identityConfirmed, isTrue);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('onboarding-next')))
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), null);
      },
    );
  }
  testWidgets(
    'local confirmation precedes automatic online review, which still needs explicit confirmation',
    (tester) async {
      final mainPort = FakeOnboardingPort(
        facts(onlineSetupPending: true, matched: false),
      );
      final port = FakeOnlinePort()
        ..snapshot = OnlineReviewWire.parse(
          onlineWire(state: 'identityCheckRequired', local: 'Pilot-Example'),
        );
      final online = OnlineReviewController(port);
      addTearDown(online.dispose);
      addTearDown(port.close);
      mainPort.onAction = (action, checkpoint) async {
        if (action == OnboardingAction.confirmHandle) {
          mainPort.facts = facts(
            onlineSetupPending: true,
            matched: false,
            confirmed: true,
          );
        }
        return OnboardingReply(facts: mainPort.facts);
      };
      await pumpSetup(
        tester,
        step: OnboardingStep.identity,
        mode: OnboardingMode.online,
        port: mainPort,
        onlineReview: online,
      );
      expect(port.reads, 0);
      final next = find.byKey(const Key('onboarding-next'));
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(mainPort.actions, [OnboardingAction.confirmHandle]);
      expect(port.actions, [OnlineReviewAction.review]);
      expect(online.value.canConfirm, true);
      expect(tester.widget<FilledButton>(next).onPressed, null);
    },
  );
  testWidgets(
    'authorization keeps cancellation available and blocks route close and mode changes until actual return',
    (tester) async {
      final port = FakeOnlinePort();
      final online = OnlineReviewController(port);
      addTearDown(online.dispose);
      addTearDown(port.close);
      final login = Completer<OnlineReviewSnapshot>(),
          cancel = Completer<OnlineReviewSnapshot>();
      port.onAction = (action) =>
          action == OnlineReviewAction.login ? login.future : cancel.future;
      var closed = false;
      await pumpSetup(
        tester,
        step: OnboardingStep.mode,
        mode: OnboardingMode.online,
        observation: facts(
          confirmed: true,
          onlineSetupPending: true,
          signedIn: false,
          matched: false,
        ),
        onlineReview: online,
        onClose: () {
          closed = true;
        },
      );
      final signIn = find.byKey(const Key('online-review-login'));
      await tester.ensureVisible(signIn);
      await tester.tap(signIn);
      await tester.pump();
      expect(online.canCancelLogin, true);
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('onboarding-close')))
            .onPressed,
        null,
      );
      expect(
        tester
            .widget<RadioListTile<OnboardingMode>>(
              find.byKey(const Key('onboarding-mode-local')),
            )
            .enabled,
        false,
      );
      final stop = find.byKey(const Key('online-review-cancel'));
      await tester.ensureVisible(stop);
      await tester.tap(stop);
      await tester.pump();
      expect(online.value.busy, true);
      expect(online.value.action, OnlineReviewAction.cancel);
      login.complete(OnlineReviewWire.parse(reviewWire()));
      await tester.pump();
      expect(online.value.busy, true);
      expect(closed, false);
      cancel.complete(
        OnlineReviewWire.parse(
          onlineWire(mode: 'local', state: 'notStarted', revision: 4),
        ),
      );
      await tester.pumpAndSettle();
      expect(online.value.busy, false);
      expect(online.value.snapshot.modeState, OnlineReviewModeState.local);
    },
  );
  testWidgets(
    'all waiting and refusal states have localized guidance without inferred mismatch or readiness',
    (tester) async {
      final port = FakeOnlinePort();
      final online = OnlineReviewController(port);
      addTearDown(online.dispose);
      addTearDown(port.close);
      await pumpSetup(
        tester,
        step: OnboardingStep.mode,
        mode: OnboardingMode.online,
        observation: facts(confirmed: true, onlineSetupPending: true),
        onlineReview: online,
      );
      for (final state in OnlineReviewState.values) {
        final accountOnly =
            state == OnlineReviewState.accountReviewRequired ||
            state == OnlineReviewState.accountConfirmedForHandoff;
        final installed =
            state == OnlineReviewState.installedReviewRequired ||
            state == OnlineReviewState.boundOnlineIdentity;
        port.snapshot = OnlineReviewWire.parse(
          accountOnly || installed
              ? {
                  ...onlineWire(
                    state: state.name,
                    mode: installed ? 'online' : 'signInRequired',
                    local: installed ? 'Pilot-Example' : null,
                    remote: 'Pilot-Example',
                    key:
                        state == OnlineReviewState.accountReviewRequired ||
                            state == OnlineReviewState.installedReviewRequired
                        ? 'a' * 32
                        : null,
                  ),
                  'schemaVersion': 2,
                  'retainsSession': accountOnly,
                }
              : state == OnlineReviewState.reviewRequired
              ? reviewWire()
              : state == OnlineReviewState.confirmedForHandoff
              ? reviewWire(confirmed: true)
              : onlineWire(state: state.name),
          retainedProtocol: accountOnly || installed,
        );
        await online.refresh();
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
        expect(port.actions, isEmpty);
        expect(
          online.value.canConfirm,
          state == OnlineReviewState.reviewRequired ||
              state == OnlineReviewState.accountReviewRequired ||
              state == OnlineReviewState.installedReviewRequired,
        );
      }
    },
  );
  testWidgets(
    'installed online guide exposes game identity review and confirmation',
    (tester) async {
      Map<String, Object?> installed(String state) => {
        ...onlineWire(
          mode: 'online',
          state: state,
          local: 'Pilot-Example',
          remote: 'Pilot-Example',
          key: state == 'installedReviewRequired' ? 'a' * 32 : null,
        ),
        'schemaVersion': 2,
        'retainsSession': false,
      };
      final port = FakeOnlinePort()
        ..snapshot = OnlineReviewWire.parse(
          installed('identityCheckRequired'),
          retainedProtocol: true,
        );
      port.onAction = (action) async => port.snapshot = OnlineReviewWire.parse(
        installed(
          action == OnlineReviewAction.review
              ? 'installedReviewRequired'
              : 'boundOnlineIdentity',
        ),
        retainedProtocol: true,
      );
      final online = OnlineReviewController(port);
      addTearDown(online.dispose);
      addTearDown(port.close);
      await pumpSetup(
        tester,
        step: OnboardingStep.mode,
        mode: OnboardingMode.online,
        observation: facts(
          confirmed: true,
          matched: false,
          activeMode: OnboardingMode.online,
          publicationSuspended: false,
        ),
        onlineReview: online,
      );

      final confirm = find.byKey(const Key('online-review-confirm'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(port.actions, [
        OnlineReviewAction.review,
        OnlineReviewAction.confirm,
      ]);
      expect(online.value.snapshot.identityConfirmed, true);
      expect(tester.takeException(), null);
    },
  );
  testWidgets('synthetic online review capture uses existing product tokens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 980);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = FakeOnlinePort()
      ..snapshot = OnlineReviewWire.parse(reviewWire());
    final online = OnlineReviewController(port);
    addTearDown(online.dispose);
    addTearDown(port.close);
    await pumpSetup(
      tester,
      step: OnboardingStep.mode,
      mode: OnboardingMode.online,
      observation: facts(confirmed: true, onlineSetupPending: true),
      onlineReview: online,
    );
    expect(
      find.text(
        const OnboardingCopy(Locale('zh', 'CN')).text('accountCard.title'),
      ),
      findsOneWidget,
    );
    final capture = Platform.environment['STARBRIDGE_ONBOARDING_CAPTURE_PATH'];
    if (capture != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('onboarding-capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          await File(capture).writeAsBytes(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          );
        } finally {
          image.dispose();
        }
      });
    }
    expect(tester.takeException(), null);
  });
}
