import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_review_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_controller.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

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
  for (final state in ['reauthorizationRequired', 'sessionExpired']) {
    test(
      'reauthorization requires separate capability and explicit action: $state',
      () async {
        final f = OnlineBridgeFixture(retainedProtocol: true);
        addTearDown(f.close);
        f.payload = retainedWire(state: state);
        expect((await f.adapter.read()).canReauthorize, false);
        expect(
          () => f.adapter.execute(OnlineReviewAction.reauthorize, 7),
          throwsStateError,
        );
        f.session.acceptHostCapabilities([
          BridgeOnlineReviewAdapter.retainedCapability,
          BridgeOnlineReviewAdapter.reauthorizationCapability,
        ]);
        expect((await f.adapter.read()).canReauthorize, true);
        expect(
          f.requests.where((r) => r.name.endsWith('.reauthorize')),
          isEmpty,
        );
        f.payload = retainedReview();
        final reply = await f.adapter.execute(
          OnlineReviewAction.reauthorize,
          7,
        );
        expect(reply.canConfirm, true);
        expect(reply.identityConfirmed, false);
        expect(f.requests.last.name, 'onboarding.onlineReview.v2.reauthorize');
        expect(f.requests.last.payload, {'schemaVersion': 2, 'revision': 7});
        expect(f.requests.last.accountContext, null);
      },
    );
  }
  test('capability removal prevents the previously displayed reauthorization action', () async {
    final f = OnlineBridgeFixture(retainedProtocol: true);
    addTearDown(f.close);
    f.session.acceptHostCapabilities([
      BridgeOnlineReviewAdapter.retainedCapability,
      BridgeOnlineReviewAdapter.reauthorizationCapability,
    ]);
    f.payload = retainedWire(state: 'reauthorizationRequired');
    await f.adapter.read();
    f.session.acceptHostCapabilities([
      BridgeOnlineReviewAdapter.retainedCapability,
    ]);
    expect(
      () => f.adapter.execute(OnlineReviewAction.reauthorize, 7),
      throwsStateError,
    );
    expect(f.requests, hasLength(1));
  });
  test('reauthorization retains its exact original cancellation receipt after invalidation', () async {
    final f = OnlineBridgeFixture(retainedProtocol: true);
    final controller = OnlineReviewController(f.adapter);
    addTearDown(controller.dispose);
    addTearDown(f.close);
    f.session.acceptHostCapabilities([
      BridgeOnlineReviewAdapter.retainedCapability,
      BridgeOnlineReviewAdapter.reauthorizationCapability,
    ]);
    f.payload = retainedWire(state: 'reauthorizationRequired');
    await controller.refresh();
    final authEntered = Completer<BridgeEnvelope>(),
        cancelEntered = Completer<BridgeEnvelope>();
    f.onRequest = (request) async {
      if (request.name.endsWith('.reauthorize')) {
        authEntered.complete(request);
      } else if (request.name.endsWith('.cancel')) {
        cancelEntered.complete(request);
      } else {
        await f.respond(request);
      }
    };
    final auth = controller.execute(OnlineReviewAction.reauthorize);
    final request = await authEntered.future;
    await f.pair.host.send(
      const BridgeEnvelope(
        protocolVersion: 1,
        messageType: 'event',
        name: 'onboarding.changed',
        sessionGeneration: 7,
        sequence: 1,
        payload: {},
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.canCancelLogin, true);
    final cancel = controller.execute(OnlineReviewAction.cancel);
    final actual = await cancelEntered.future;
    await f.respond(request, value: retainedReview());
    await auth;
    expect(controller.value.busy, true);
    f.payload = retainedWire(mode: 'offline', state: 'notStarted', revision: 8);
    await f.respond(actual);
    await cancel;
    expect(controller.value.snapshot.modeState, OnlineReviewModeState.offline);
    expect(controller.value.canConfirm, false);
  });
  test(
    'capability removal while authorizing rejects the late successful review',
    () async {
      final f = OnlineBridgeFixture(retainedProtocol: true);
      addTearDown(f.close);
      f.session.acceptHostCapabilities([
        BridgeOnlineReviewAdapter.retainedCapability,
        BridgeOnlineReviewAdapter.reauthorizationCapability,
      ]);
      f.payload = retainedWire(state: 'reauthorizationRequired');
      await f.adapter.read();
      final entered = Completer<BridgeEnvelope>();
      f.onRequest = (request) async {
        entered.complete(request);
      };
      final work = f.adapter.execute(OnlineReviewAction.reauthorize, 7);
      final rejected = expectLater(work, throwsStateError);
      final original = await entered.future;
      f.session.acceptHostCapabilities([
        BridgeOnlineReviewAdapter.retainedCapability,
      ]);
      await f.respond(original, value: retainedReview());
      await rejected;
      expect(
        () => f.adapter.execute(
          OnlineReviewAction.confirm,
          7,
          confirmationKey: '11111111111111111111111111111111',
        ),
        throwsStateError,
      );
    },
  );
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    testWidgets(
      'expired retained recovery is explicit and fits small text-scaled screen $locale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 840);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final port = FakeOnlinePort()
          ..snapshot = OnlineReviewWire.parse(
            retainedWire(state: 'reauthorizationRequired'),
            retainedProtocol: true,
            reauthorizationSupported: true,
          );
        final controller = OnlineReviewController(port);
        addTearDown(controller.dispose);
        addTearDown(port.close);
        port.onAction = (_) async => OnlineReviewWire.parse(
          retainedReview(),
          retainedProtocol: true,
          reauthorizationSupported: true,
        );
        await pumpSetup(
          tester,
          step: OnboardingStep.identity,
          mode: OnboardingMode.online,
          observation: facts(confirmed: true, onlineSetupPending: true),
          onlineReview: controller,
          locale: locale,
          scale: 1.6,
        );
        expect(port.actions, isEmpty);
        expect(
          find.text(OnboardingCopy(locale).text('onlineReview.reauthorize')),
          findsOneWidget,
        );
        final action = find.byKey(const Key('online-review-reauthorize'));
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(port.actions, [OnlineReviewAction.reauthorize]);
        expect(controller.value.canConfirm, true);
        expect(controller.value.snapshot.identityConfirmed, false);
        expect(tester.takeException(), null);
      },
    );
  }
}
