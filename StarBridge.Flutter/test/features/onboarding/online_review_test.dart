import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_review_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_onboarding_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_controller.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_controller.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'onboarding_test_support.dart';
import 'bridge_onboarding_adapter_test.dart' show wire;
import 'online_review_test_support.dart';

void main() {
  test(
    'handoff waiting is not identity confirmation and cannot restart review',
    () async {
      final snapshot = OnlineReviewWire.parse(
        onlineWire(state: 'operationInProgress', local: 'Pilot-Example'),
      );
      expect(snapshot.canReview, false);
      expect(snapshot.canLogin, false);
      expect(snapshot.canConfirm, false);
      expect(snapshot.identityConfirmed, false);
      expect(snapshot.canCancel, true);
      final port = FakeOnlinePort()..snapshot = snapshot;
      final controller = OnlineReviewController(port);
      addTearDown(controller.dispose);
      addTearDown(port.close);
      await controller.refresh();
      await controller.execute(OnlineReviewAction.review);
      expect(port.actions, isEmpty);
    },
  );
  test('fixed wire shape rejects missing unknown private and contradictory observations', () {
    expect(OnlineReviewWire.parse(reviewWire()).canConfirm, true);
    expect(
      OnlineReviewWire.parse(reviewWire(confirmed: true)).identityConfirmed,
      true,
    );
    final badIdentities = <Map<String, Object?>>[
      {'state': 'ready'},
      {...(onlineWire()['identity'] as Map<String, Object?>)}
        ..remove('confirmationKey'),
      {
        ...(reviewWire()['identity'] as Map<String, Object?>),
        'confirmationKey': 'private/path',
      },
      {
        ...(reviewWire()['identity'] as Map<String, Object?>),
        'localHandle': null,
      },
      {
        ...(reviewWire()['identity'] as Map<String, Object?>),
        'authoritativeHandle': 'Other-Pilot',
      },
      {
        ...(reviewWire()['identity'] as Map<String, Object?>),
        'accountDisplayName': 'Private\nData',
      },
      {
        ...(reviewWire()['identity'] as Map<String, Object?>),
        'subject': 'private',
      },
      {
        ...(reviewWire(confirmed: true)['identity'] as Map<String, Object?>),
        'confirmationKey': '11111111111111111111111111111111',
      },
    ];
    for (final value in [
      {...onlineWire()}..remove('revision'),
      {...onlineWire(), 'schemaVersion': true},
      {...onlineWire(), 'revision': -1},
      {...onlineWire(), 'revision': 1.5},
      {...onlineWire(), 'modeState': 'installed'},
      {...reviewWire(), 'modeState': 'local'},
      for (final identity in badIdentities)
        {...onlineWire(), 'identity': identity},
    ]) {
      expect(() => OnlineReviewWire.parse(value), throwsFormatException);
    }
    expect(const OnlineReviewSnapshot().identityConfirmed, false);
  });
  test(
    'only negotiated-version exact staged-auth routes are account agnostic',
    () {
      for (final action in [
        'read',
        ...OnlineReviewAction.values
            .where(
              (a) =>
                  a != OnlineReviewAction.resume &&
                  a != OnlineReviewAction.reauthorize,
            )
            .map((a) => a.name),
      ]) {
        expect(
          () => BridgeRequestPolicy.requireAccountContext(
            'onboarding.onlineReview.$action',
            null,
          ),
          returnsNormally,
        );
      }
      for (final action in [
        'read',
        ...OnlineReviewAction.values.map((a) => a.name),
      ]) {
        expect(
          () => BridgeRequestPolicy.requireAccountContext(
            'onboarding.onlineReview.v2.$action',
            null,
          ),
          returnsNormally,
        );
      }
      for (final action in [
        'finish',
        'activate',
        'loginAnything',
        'import',
        'resume',
        'reauthorize',
      ]) {
        expect(
          () => BridgeRequestPolicy.requireAccountContext(
            'onboarding.onlineReview.$action',
            null,
          ),
          throwsA(isA<BridgeAccountContextRequiredException>()),
        );
      }
      for (final action in ['finish', 'activate', 'resumeAnything', 'import']) {
        expect(
          () => BridgeRequestPolicy.requireAccountContext(
            'onboarding.onlineReview.v2.$action',
            null,
          ),
          throwsA(isA<BridgeAccountContextRequiredException>()),
        );
      }
    },
  );
  test(
    'subset capability cannot become full onboarding availability',
    () async {
      final f = OnlineBridgeFixture();
      addTearDown(f.close);
      expect(
        (await BridgeOnboardingAdapter(f.session).read()).facts.available,
        false,
      );
      expect(f.requests, isEmpty);
      final missing = OnlineBridgeFixture(capability: false);
      addTearDown(missing.close);
      expect((await missing.adapter.read()).revision, null);
      expect(
        () => missing.adapter.execute(OnlineReviewAction.begin, 0),
        throwsStateError,
      );
      expect(missing.requests, isEmpty);
    },
  );
  test(
    'bridge sends only observed revision and one-use key, no account identity',
    () async {
      final f = OnlineBridgeFixture();
      addTearDown(f.close);
      f.payload = reviewWire();
      final snapshot = await f.adapter.read();
      f.payload = reviewWire(confirmed: true);
      final response = await f.adapter.execute(
        OnlineReviewAction.confirm,
        3,
        confirmationKey: snapshot.confirmationKey,
      );
      expect(response.identityConfirmed, true);
      expect(f.requests.last.accountContext, null);
      expect(f.requests.last.payload, {
        'schemaVersion': 1,
        'revision': 3,
        'confirmationKey': snapshot.confirmationKey,
      });
      expect(
        () => f.adapter.execute(
          OnlineReviewAction.confirm,
          3,
          confirmationKey: snapshot.confirmationKey,
        ),
        throwsStateError,
      );
    },
  );
  test('late login reply cannot replace the actual local cancellation acknowledgement', () async {
    final f = OnlineBridgeFixture();
    addTearDown(f.close);
    await f.adapter.read();
    final entered = Completer<BridgeEnvelope>();
    f.onRequest = (request) async {
      if (request.name.endsWith('login')) {
        entered.complete(request);
      } else {
        await f.respond(
          request,
          value: onlineWire(mode: 'local', state: 'notStarted', revision: 4),
        );
      }
    };
    final login = f.adapter.execute(OnlineReviewAction.login, 3);
    final rejected = expectLater(login, throwsStateError);
    final request = await entered.future;
    final local = await f.adapter.execute(OnlineReviewAction.cancel, 3);
    await f.respond(request, value: reviewWire());
    await rejected;
    expect(local.modeState, OnlineReviewModeState.local);
    expect(
      () => f.adapter.execute(
        OnlineReviewAction.confirm,
        3,
        confirmationKey: '11111111111111111111111111111111',
      ),
      throwsStateError,
    );
  });
  test('capability withdrawal and account-context leakage reject awaited responses', () async {
    final f = OnlineBridgeFixture();
    addTearDown(f.close);
    final entered = Completer<BridgeEnvelope>();
    f.onRequest = (request) async {
      entered.complete(request);
    };
    final pending = f.adapter.read();
    final rejected = expectLater(pending, throwsStateError);
    final request = await entered.future;
    f.session.acceptHostCapabilities([]);
    await f.respond(request);
    await rejected;
    f.session.acceptHostCapabilities([BridgeOnlineReviewAdapter.capability]);
    f.onRequest = (request) => f.respond(
      request,
      context: const BridgeAccountContext(
        environment: 'private',
        authority: 'private',
        subject: 'private',
      ),
    );
    await expectLater(f.adapter.read(), throwsStateError);
  });
  test(
    'opening and polling never authenticates or confirms automatically',
    () async {
      final port = FakeOnlinePort()
        ..snapshot = OnlineReviewWire.parse(
          onlineWire(mode: 'local', state: 'notStarted', revision: 2),
        );
      final c = OnlineReviewController(port);
      addTearDown(c.dispose);
      addTearDown(port.close);
      await c.refresh();
      await c.refresh();
      expect(port.actions, isEmpty);
      await c.signIn();
      expect(port.actions, [
        OnlineReviewAction.begin,
        OnlineReviewAction.login,
      ]);
      expect(c.value.snapshot.state, OnlineReviewState.needsLocalIdentity);
      expect(c.value.snapshot.identityConfirmed, false);
      await c.execute(OnlineReviewAction.review);
      expect(c.value.canConfirm, true);
      await c.execute(OnlineReviewAction.confirm);
      expect(c.value.snapshot.identityConfirmed, true);
      expect(port.actions.last, OnlineReviewAction.confirm);
    },
  );
  test('cancel remains waiting until its own result, late login cannot clear or replace it', () async {
    final port = FakeOnlinePort();
    final c = OnlineReviewController(port);
    addTearDown(c.dispose);
    addTearDown(port.close);
    await c.refresh();
    final login = Completer<OnlineReviewSnapshot>(),
        cancel = Completer<OnlineReviewSnapshot>();
    port.onAction = (action) =>
        action == OnlineReviewAction.login ? login.future : cancel.future;
    final entering = c.signIn();
    expect(c.canCancelLogin, true);
    final cancelling = c.execute(OnlineReviewAction.cancel);
    expect(c.value.busy, true);
    expect(c.value.action, OnlineReviewAction.cancel);
    expect(c.canCancelLogin, false);
    login.complete(OnlineReviewWire.parse(reviewWire()));
    await entering;
    expect(c.value.busy, true);
    expect(c.value.action, OnlineReviewAction.cancel);
    cancel.complete(
      OnlineReviewWire.parse(
        onlineWire(mode: 'local', state: 'notStarted', revision: 4),
      ),
    );
    await cancelling;
    expect(c.value.snapshot.modeState, OnlineReviewModeState.local);
    expect(c.value.busy, false);
    expect(c.value.canConfirm, false);
  });
  test(
    'invalidations reject a pending review and reread without automatic writes',
    () async {
      final port = FakeOnlinePort();
      final c = OnlineReviewController(port);
      addTearDown(c.dispose);
      addTearDown(port.close);
      await c.refresh();
      final held = Completer<OnlineReviewSnapshot>();
      port.onAction = (_) => held.future;
      final pending = c.execute(OnlineReviewAction.review);
      port.snapshot = const OnlineReviewSnapshot();
      port.events.add(null);
      expect(c.value.canConfirm, false);
      held.complete(OnlineReviewWire.parse(reviewWire()));
      await pending;
      await Future<void>.delayed(Duration.zero);
      expect(c.value.snapshot.state, OnlineReviewState.unavailable);
      expect(c.value.canConfirm, false);
      expect(port.actions, [OnlineReviewAction.review]);
      expect(port.reads, 2);
    },
  );
  test(
    'failed confirmation loses the displayed key and needs a fresh read',
    () async {
      final port = FakeOnlinePort()
        ..snapshot = OnlineReviewWire.parse(reviewWire());
      final c = OnlineReviewController(port);
      addTearDown(c.dispose);
      addTearDown(port.close);
      await c.refresh();
      port.onAction = (_) =>
          Future.error(StateError('Synthetic readback failed'));
      await c.execute(OnlineReviewAction.confirm);
      expect(c.value.error, true);
      expect(c.value.canConfirm, false);
      await c.execute(OnlineReviewAction.confirm);
      expect(port.actions.length, 1);
      await c.refresh();
      expect(c.value.canConfirm, true);
      expect(c.value.snapshot.identityConfirmed, false);
    },
  );
  test('trusted pending route allows local confirmation before SCM matching, not online completion', () async {
    final p = FakeOnboardingPort(
      facts(onlineSetupPending: true, matched: false),
    );
    p.restored = OnboardingCheckpoint(
      step: OnboardingStep.identity,
      mode: OnboardingMode.online,
      sourceKey: p.facts.sourceKey,
      evidenceKey: p.facts.evidenceKey,
    );
    final c = OnboardingController(p);
    addTearDown(c.dispose);
    await c.initialize();
    expect(c.value.modeApplied, true);
    expect(c.canContinue, false);
    expect(c.canConfirmLocalIdentity, true);
    await c.run(OnboardingAction.confirmHandle);
    expect(p.actions, [OnboardingAction.confirmHandle]);
    p.facts = facts(onlineSetupPending: true, confirmed: true);
    await c.refresh();
    await c.next();
    await c.next();
    await c.next();
    expect(c.value.step, OnboardingStep.verify);
    await c.next();
    expect(c.value.step, OnboardingStep.summary);
    await c.next();
    expect(p.finishes, 1);
    expect(c.value.completed, false);
    expect(c.value.error, true);
  });
  test(
    'pending online setup cannot bypass actual suspension in the full wire',
    () {
      final raw = wire();
      final f = raw['facts'] as Map<String, Object?>;
      f['onlineSetupPending'] = true;
      expect(OnboardingWire.parse(raw).$2.facts.onlineSetupPending, true);
      f['publicationSuspended'] = false;
      expect(() => OnboardingWire.parse(raw), throwsFormatException);
      f['publicationSuspended'] = true;
      f['activeMode'] = 'online';
      expect(() => OnboardingWire.parse(raw), throwsFormatException);
    },
  );
}
