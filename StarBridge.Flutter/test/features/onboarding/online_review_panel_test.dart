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
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
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
          step: OnboardingStep.identity,
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
          facts(confirmed: true, onlineSetupPending: true),
        );
        await pumpSetup(
          tester,
          step: OnboardingStep.identity,
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
        await tester.ensureVisible(confirm);
        await tester.pumpAndSettle();
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(port.actions, [OnlineReviewAction.confirm]);
        expect(mainPort.finishes, 0);
        expect(mainPort.saves, 0);
        expect(tester.takeException(), null);
      },
    );
  }
  testWidgets(
    'online route can confirm the local log before matching SCM; it still cannot advance',
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
      expect(port.actions, isEmpty);
      final confirm = find.byKey(const Key('onboarding-confirm-local-handle'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(mainPort.actions, [OnboardingAction.confirmHandle]);
      expect(port.reads, 1);
      expect(port.actions, isEmpty);
      expect(online.value.canConfirm, false);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('onboarding-next')))
            .onPressed,
        null,
      );
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
        step: OnboardingStep.identity,
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
        step: OnboardingStep.identity,
        mode: OnboardingMode.online,
        observation: facts(
          confirmed: true,
          matched: false,
          activeMode: OnboardingMode.online,
          publicationSuspended: false,
        ),
        onlineReview: online,
      );
      final check = find.byKey(const Key('online-review-check'));
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
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
      step: OnboardingStep.identity,
      mode: OnboardingMode.online,
      observation: facts(confirmed: true, onlineSetupPending: true),
      onlineReview: online,
    );
    expect(
      find.text(
        const OnboardingCopy(Locale('zh', 'CN')).text('onlineReview.title'),
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
