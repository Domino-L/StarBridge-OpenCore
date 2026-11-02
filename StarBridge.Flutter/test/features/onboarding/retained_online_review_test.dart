import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_review_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_controller.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'online_review_test_support.dart';

Map<String, Object?> retainedWire({
  String mode = 'signInRequired',
  String state = 'signInRequired',
  int revision = 7,
}) => {
  ...onlineWire(mode: mode, state: state, revision: revision),
  'schemaVersion': 2,
  'retainsSession': true,
};
Map<String, Object?> retainedReview({bool confirmed = false}) => {
  ...reviewWire(confirmed: confirmed),
  'schemaVersion': 2,
  'revision': 7,
  'retainsSession': true,
};

void main() {
  for (final change in ['generation', 'protocol']) {
    test(
      'original auth cancellation cannot cross $change replacement',
      () async {
        final f = OnlineBridgeFixture(retainedProtocol: true);
        addTearDown(f.close);
        f.payload = retainedWire();
        await f.adapter.read();
        final entered = Completer<BridgeEnvelope>();
        f.onRequest = (request) async {
          entered.complete(request);
        };
        final resume = f.adapter.execute(OnlineReviewAction.resume, 7);
        final rejected = expectLater(resume, throwsA(anyOf(isA<Exception>(), isA<StateError>())));
        final original = await entered.future;
        if (change == 'generation') {
          f.session.advanceGeneration(8);
        } else {
          f.session.acceptHostCapabilities([
            BridgeOnlineReviewAdapter.capability,
          ]);
        }
        expect(
          () => f.adapter.execute(OnlineReviewAction.cancel, 7),
          throwsStateError,
        );
        expect(f.requests, hasLength(2));
        await f.respond(original, value: retainedReview());
        await rejected;
      },
    );
  }
  test('pending-auth receipt permits only exact revision and a single cancellation wait', () async {
    final f = OnlineBridgeFixture(retainedProtocol: true);
    addTearDown(f.close);
    f.payload = retainedWire();
    await f.adapter.read();
    final entered = Completer<BridgeEnvelope>(),
        cancelEntered = Completer<BridgeEnvelope>();
    f.onRequest = (request) async {
      if (request.name.endsWith('.resume')) {
        entered.complete(request);
      } else {
        cancelEntered.complete(request);
      }
    };
    final resume = f.adapter.execute(OnlineReviewAction.resume, 7);
    final rejected = expectLater(resume, throwsStateError);
    final original = await entered.future;
    expect(
      () => f.adapter.execute(OnlineReviewAction.resume, 7),
      throwsStateError,
    );
    expect(
      () => f.adapter.execute(OnlineReviewAction.cancel, 8),
      throwsStateError,
    );
    final cancel = f.adapter.execute(OnlineReviewAction.cancel, 7);
    final actual = await cancelEntered.future;
    expect(
      () => f.adapter.execute(OnlineReviewAction.cancel, 7),
      throwsStateError,
    );
    await f.respond(original, value: retainedReview());
    await rejected;
    expect(
      () => f.adapter.execute(OnlineReviewAction.cancel, 7),
      throwsStateError,
    );
    await f.respond(
      actual,
      value: retainedWire(mode: 'offline', state: 'notStarted', revision: 8),
    );
    await cancel;
    expect(f.requests, hasLength(3));
  });
  for (final retained in [false, true]) {
    for (final event in [
      'bootstrap.invalidated',
      'gameLog.changed',
      'onboarding.changed',
    ]) {
      test(
        'same-generation $event retains actual ${retained ? 'resume' : 'login'} cancellation route',
        () async {
          final f = OnlineBridgeFixture(retainedProtocol: retained);
          final controller = OnlineReviewController(f.adapter);
          addTearDown(controller.dispose);
          addTearDown(f.close);
          f.payload = retained ? retainedWire() : onlineWire();
          await controller.refresh();
          final authEntered = Completer<BridgeEnvelope>(),
              cancelEntered = Completer<BridgeEnvelope>();
          BridgeEnvelope? cancellation;
          f.onRequest = (request) async {
            if (request.name.endsWith(retained ? '.resume' : '.login')) {
              authEntered.complete(request);
            } else if (request.name.endsWith('.cancel')) {
              cancellation = request;
              cancelEntered.complete(request);
            } else {
              await f.respond(request);
            }
          };
          final auth = controller.signIn();
          final original = await authEntered.future;
          await f.pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'event',
              name: event,
              sessionGeneration: 7,
              sequence: 1,
              payload: const {},
            ),
          );
          await Future<void>.delayed(Duration.zero);
          expect(controller.canCancelLogin, true);
          expect(controller.value.canConfirm, false);
          final cancelling = controller.execute(OnlineReviewAction.cancel);
          try {
            final actual = await cancelEntered.future.timeout(
              const Duration(seconds: 1),
            );
            expect(actual.sessionGeneration, 7);
            expect(actual.accountContext, null);
            expect(actual.payload, {
              'schemaVersion': retained ? 2 : 1,
              'revision': retained ? 7 : 3,
            });
            await f.respond(
              original,
              value: retained ? retainedReview() : reviewWire(),
            );
            await auth;
            expect(controller.value.busy, true);
            expect(controller.value.action, OnlineReviewAction.cancel);
            f.payload = retained
                ? retainedWire(
                    mode: 'offline',
                    state: 'notStarted',
                    revision: 8,
                  )
                : onlineWire(mode: 'local', state: 'notStarted', revision: 4);
            await f.respond(actual);
            await cancelling;
            await Future<void>.delayed(Duration.zero);
            expect(controller.value.canConfirm, false);
            expect(
              controller.value.snapshot.modeState,
              retained
                  ? OnlineReviewModeState.offline
                  : OnlineReviewModeState.local,
            );
          } finally {
            // Even a failed assertion releases every original fixture request.
            await f.respond(
              original,
              value: retained ? retainedReview() : reviewWire(),
            );
            if (cancellation != null) await f.respond(cancellation!);
            await auth;
            await cancelling;
          }
        },
      );
    }
  }
  test('v2 retained observations never become browser-login permission', () {
    final offline = OnlineReviewWire.parse(
      retainedWire(mode: 'offline', state: 'notStarted'),
      retainedProtocol: true,
    );
    expect(offline.canBegin, true);
    expect(offline.canLogin, false);
    final pending = OnlineReviewWire.parse(
      retainedWire(),
      retainedProtocol: true,
    );
    expect(pending.canResume, true);
    expect(pending.canLogin, false);
    expect(pending.identityConfirmed, false);
    final reviewed = OnlineReviewWire.parse(
      retainedReview(),
      retainedProtocol: true,
    );
    expect(reviewed.canConfirm, true);
    expect(reviewed.canResume, false);
    final confirmed = OnlineReviewWire.parse(
      retainedReview(confirmed: true),
      retainedProtocol: true,
    );
    expect(confirmed.identityConfirmed, true);
    expect(confirmed.modeState, OnlineReviewModeState.signInRequired);
    for (final bad in [
      {...retainedWire()}..remove('retainsSession'),
      {...retainedWire(), 'retainsSession': 'true'},
      {
        ...retainedWire(mode: 'offline', state: 'notStarted'),
        'retainsSession': false,
      },
      retainedWire(mode: 'local', state: 'notStarted'),
      retainedWire(mode: 'online', state: 'notStarted'),
      {...retainedWire(), 'refreshToken': 'private'},
      {...retainedWire(), 'schemaVersion': 1},
    ]) {
      expect(
        () => OnlineReviewWire.parse(bad, retainedProtocol: true),
        throwsFormatException,
      );
    }
    expect(() => OnlineReviewWire.parse(retainedWire()), throwsFormatException);
    expect(
      () => OnlineReviewWire.parse(onlineWire(), retainedProtocol: true),
      throwsFormatException,
    );
  });

  test(
    'negotiated v2 sends explicit resume and one-use confirmation, never login',
    () async {
      final f = OnlineBridgeFixture(retainedProtocol: true);
      addTearDown(f.close);
      f.payload = retainedWire(
        mode: 'offline',
        state: 'notStarted',
        revision: 6,
      );
      await f.adapter.read();
      f.payload = retainedWire();
      await f.adapter.execute(OnlineReviewAction.begin, 6);
      expect(
        () => f.adapter.execute(OnlineReviewAction.login, 7),
        throwsStateError,
      );
      f.payload = retainedReview();
      final review = await f.adapter.execute(OnlineReviewAction.resume, 7);
      expect(review.canConfirm, true);
      f.payload = retainedReview(confirmed: true);
      await f.adapter.execute(
        OnlineReviewAction.confirm,
        7,
        confirmationKey: review.confirmationKey,
      );
      expect(f.requests.map((r) => r.name), [
        'onboarding.onlineReview.v2.read',
        'onboarding.onlineReview.v2.begin',
        'onboarding.onlineReview.v2.resume',
        'onboarding.onlineReview.v2.confirm',
      ]);
      for (final request in f.requests) {
        expect(request.accountContext, null);
        expect(request.payload['schemaVersion'], 2);
        expect(
          request.payload.keys.every(
            {'schemaVersion', 'revision', 'confirmationKey'}.contains,
          ),
          true,
        );
      }
      expect(
        () => f.adapter.execute(
          OnlineReviewAction.confirm,
          7,
          confirmationKey: review.confirmationKey,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'protocol downgrade invalidates review before any confirmation write',
    () async {
      final f = OnlineBridgeFixture(retainedProtocol: true);
      addTearDown(f.close);
      f.payload = retainedReview();
      final observed = await f.adapter.read();
      f.session.acceptHostCapabilities([BridgeOnlineReviewAdapter.capability]);
      expect(
        () => f.adapter.execute(
          OnlineReviewAction.confirm,
          7,
          confirmationKey: observed.confirmationKey,
        ),
        throwsStateError,
      );
      expect(f.requests, hasLength(1));
    },
  );

  test(
    'v2 rejects an old-version response despite successful envelope',
    () async {
      final f = OnlineBridgeFixture(retainedProtocol: true);
      addTearDown(f.close);
      f.payload = onlineWire();
      await expectLater(f.adapter.read(), throwsFormatException);
      expect(
        () => f.adapter.execute(OnlineReviewAction.begin, 3),
        throwsStateError,
      );
    },
  );

  test(
    'late retained resume reply cannot supersede real offline cancellation',
    () async {
      final f = OnlineBridgeFixture(retainedProtocol: true);
      addTearDown(f.close);
      f.payload = retainedWire();
      await f.adapter.read();
      final entered = Completer<BridgeEnvelope>();
      f.onRequest = (request) async {
        if (request.name.endsWith('.resume')) {
          entered.complete(request);
        } else {
          await f.respond(
            request,
            value: retainedWire(
              mode: 'offline',
              state: 'notStarted',
              revision: 8,
            ),
          );
        }
      };
      final resume = f.adapter.execute(OnlineReviewAction.resume, 7);
      final rejected = expectLater(resume, throwsStateError);
      final request = await entered.future;
      final cancelled = await f.adapter.execute(OnlineReviewAction.cancel, 7);
      await f.respond(request, value: retainedReview());
      await rejected;
      expect(cancelled.modeState, OnlineReviewModeState.offline);
      expect(cancelled.retainsSession, true);
      expect(cancelled.canBegin, true);
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

  test(
    'controller begins retained resume and supports cancellation while waiting',
    () async {
      final port = FakeOnlinePort()
        ..snapshot = OnlineReviewWire.parse(
          retainedWire(mode: 'offline', state: 'notStarted', revision: 6),
          retainedProtocol: true,
        );
      final controller = OnlineReviewController(port);
      addTearDown(controller.dispose);
      addTearDown(port.close);
      final entered = Completer<void>(),
          release = Completer<OnlineReviewSnapshot>();
      port.onAction = (action) async {
        if (action == OnlineReviewAction.begin) {
          return OnlineReviewWire.parse(retainedWire(), retainedProtocol: true);
        }
        if (action == OnlineReviewAction.resume) {
          entered.complete();
          return release.future;
        }
        if (action == OnlineReviewAction.cancel) {
          return OnlineReviewWire.parse(
            retainedWire(mode: 'offline', state: 'notStarted', revision: 8),
            retainedProtocol: true,
          );
        }
        throw StateError('Retained flow cannot login or implicitly confirm.');
      };
      await controller.refresh();
      final attempt = controller.signIn();
      await entered.future;
      expect(controller.canCancelLogin, true);
      await controller.execute(OnlineReviewAction.cancel);
      release.complete(
        OnlineReviewWire.parse(retainedReview(), retainedProtocol: true),
      );
      await attempt;
      expect(port.actions, [
        OnlineReviewAction.begin,
        OnlineReviewAction.resume,
        OnlineReviewAction.cancel,
      ]);
      expect(
        controller.value.snapshot.modeState,
        OnlineReviewModeState.offline,
      );
      expect(controller.value.canConfirm, false);
    },
  );
}
