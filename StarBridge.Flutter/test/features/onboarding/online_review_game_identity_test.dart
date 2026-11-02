import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/account/game_identity_verification.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_first_use_game_identity.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_review_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_controller.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'onboarding_page_test.dart' show pumpSetup;
import 'onboarding_test_support.dart';
import 'online_review_test_support.dart';

final class _Verification implements GameIdentityVerificationPort {
  bool supported = true;
  int flows = 0;
  final handles = <String>[];
  @override
  bool get supportsGameIdentityVerification => supported;
  @override
  Stream<void> get supportChanges => const Stream.empty();
  @override
  void beginFlow() => flows++;
  @override
  Future<GameIdentityResult> requestVerificationCode(String handle) async {
    handles.add(handle);
    return const GameIdentityResult(
      GameIdentityOutcome.issued,
      verificationCode: 'SB-CODE-1',
      expiresInSeconds: 600,
    );
  }

  @override
  Future<GameIdentityResult> submitVerification(
    String handle,
    String contact,
  ) async => const GameIdentityResult(GameIdentityOutcome.verified);
  @override
  Future<bool> openRsiProfile() async => true;
}

final class _Port implements OnlineReviewPort, OnlineReviewGameIdentitySource {
  _Port(this.gameIdentity);
  final fake = FakeOnlinePort();
  @override
  final GameIdentityVerificationPort gameIdentity;
  @override
  Stream<void> get invalidations => fake.invalidations;
  @override
  Future<OnlineReviewSnapshot> read() => fake.read();
  @override
  Future<OnlineReviewSnapshot> execute(
    OnlineReviewAction action,
    int revision, {
    String? confirmationKey,
  }) => fake.execute(action, revision, confirmationKey: confirmationKey);
}

Future<OnlineReviewController> _pump(
  WidgetTester tester,
  _Port port,
  String state,
) async {
  tester.view.physicalSize = const Size(1100, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  port.fake.snapshot = OnlineReviewWire.parse(
    onlineWire(
      state: state,
      local: 'Pilot-Example',
      display: 'Synthetic Pilot',
    ),
  );
  final online = OnlineReviewController(port);
  addTearDown(online.dispose);
  addTearDown(port.fake.close);
  await pumpSetup(
    tester,
    step: OnboardingStep.identity,
    mode: OnboardingMode.online,
    observation: facts(confirmed: true, onlineSetupPending: true),
    onlineReview: online,
    locale: const Locale('zh', 'CN'),
  );
  await tester.pumpAndSettle();
  return online;
}

const _verify = Key('online-review-verify');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  for (final state in const [
    'verificationRequired',
    'reverifyRequired',
    'revoked',
  ]) {
    testWidgets('$state offers verification and still allows leaving', (
      tester,
    ) async {
      await _pump(tester, _Port(_Verification()), state);
      expect(find.byKey(_verify), findsOneWidget);
      expect(find.byKey(const Key('online-review-cancel')), findsOneWidget);
      final copy = OnboardingCopy(const Locale('zh', 'CN'));
      expect(
        find.text(copy.text('onlineReview.verificationRequired')),
        findsOneWidget,
      );
    });
  }

  for (final state in const [
    'mismatch',
    'verificationPending',
    'signInRequired',
  ]) {
    testWidgets('$state offers no verification', (tester) async {
      await _pump(tester, _Port(_Verification()), state);
      expect(find.byKey(_verify), findsNothing);
    });
  }

  testWidgets('no action without Host support', (tester) async {
    await _pump(
      tester,
      _Port(_Verification()..supported = false),
      'verificationRequired',
    );
    expect(find.byKey(_verify), findsNothing);
  });

  testWidgets('fills the local Handle and reviews again once verified', (
    tester,
  ) async {
    final verification = _Verification();
    final port = _Port(verification);
    await _pump(tester, port, 'verificationRequired');
    final copy = OnboardingCopy(const Locale('zh', 'CN'));
    expect(
      find.text(copy.text('onlineReview.verifyGameIdentity')),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(_verify));
    await tester.tap(find.byKey(_verify));
    await tester.pumpAndSettle();
    expect(verification.flows, 1);
    expect(find.textContaining('已从游戏日志填入'), findsOneWidget);
    await tester.tap(find.byKey(const Key('game-identity-primary')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(verification.handles, ['Pilot-Example']);
    await tester.enterText(
      find.byKey(const Key('game-identity-contact')),
      'pilot@example.test',
    );
    port.fake.actions.clear();
    await tester.tap(find.byKey(const Key('game-identity-primary')));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('game-identity-panel')), findsNothing);
    expect(port.fake.actions, contains(OnlineReviewAction.review));
    expect(tester.takeException(), isNull);
  });

  group('wire', () {
    late InMemoryBridgePair pair;
    late BridgeClientSession session;
    late StreamSubscription<BridgeEnvelope> incoming;
    final requests = <BridgeEnvelope>[];
    Map<String, Object?> reply = const {};
    int? revision = 7;

    setUp(() {
      requests.clear();
      revision = 7;
      pair = InMemoryBridgeConnection.createPair();
      session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      )..acceptHostCapabilities([BridgeFirstUseGameIdentity.capability]);
      incoming = pair.host.incoming.listen((request) {
        if (request.name == 'bridge.cancel') return;
        requests.add(request);
        pair.host.send(
          BridgeEnvelope(
            protocolVersion: 1,
            messageType: 'response',
            name: request.name,
            correlationId: request.correlationId,
            sessionGeneration: request.sessionGeneration,
            status: 'ok',
            payload: reply,
          ),
        );
      });
    });
    tearDown(() async {
      await incoming.cancel();
      await session.close();
      await pair.host.close();
    });

    test('sends the revision without an account context', () async {
      reply = {
        'schemaVersion': 1,
        'outcome': 'issued',
        'verificationCode': 'SB-1',
        'expiresInSeconds': 600,
      };
      final port = BridgeFirstUseGameIdentity(session, () => revision)
        ..beginFlow();
      final result = await port.requestVerificationCode(' Pilot_A ');
      expect(result.outcome, GameIdentityOutcome.issued);
      final sent = requests.single;
      expect(sent.name, 'onboarding.onlineReview.gameIdentity.requestCode');
      expect(sent.accountContext, isNull);
      expect(sent.payload, {
        'schemaVersion': 1,
        'revision': 7,
        'gameName': 'Pilot_A',
      });
    });

    test('a changed revision or generation sends nothing', () async {
      reply = {'schemaVersion': 1, 'outcome': 'verified'};
      final port = BridgeFirstUseGameIdentity(session, () => revision)
        ..beginFlow();
      revision = 8;
      expect(
        (await port.submitVerification('Pilot_A', 'contact-1')).outcome,
        GameIdentityOutcome.unavailable,
      );
      port.beginFlow();
      session.advanceGeneration(2);
      expect(
        (await port.submitVerification('Pilot_A', 'contact-1')).outcome,
        GameIdentityOutcome.unavailable,
      );
      expect(await port.openRsiProfile(), isFalse);
      expect(requests, isEmpty);
    });

    test('no revision means no flow', () async {
      revision = null;
      final port = BridgeFirstUseGameIdentity(session, () => revision)
        ..beginFlow();
      expect(
        (await port.requestVerificationCode('Pilot_A')).outcome,
        GameIdentityOutcome.unavailable,
      );
      expect(requests, isEmpty);
    });

    test('a malformed verify reply is unknown, never a failure', () async {
      reply = {'schemaVersion': 1, 'outcome': 'issued'};
      final port = BridgeFirstUseGameIdentity(session, () => revision)
        ..beginFlow();
      expect(
        (await port.submitVerification('Pilot_A', 'contact-1')).outcome,
        GameIdentityOutcome.outcomeUnknown,
      );
    });
  });
}
