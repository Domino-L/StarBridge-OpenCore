import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/account_page.dart';
import 'package:starbridge_flutter/features/account/account_payload_decoder.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/account/bridge_game_identity_verification.dart';
import 'package:starbridge_flutter/features/account/game_identity_verification.dart';
import 'package:starbridge_flutter/features/account/game_identity_verification_dialog.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

final class _Port implements GameIdentityVerificationPort {
  GameIdentityResult code = const GameIdentityResult(
    GameIdentityOutcome.issued,
    verificationCode: 'SB-CODE-1',
    expiresInSeconds: 600,
  );
  GameIdentityResult verify = const GameIdentityResult(
    GameIdentityOutcome.verified,
  );
  bool opened = true;
  bool supported = true;
  final _support = StreamController<void>.broadcast();
  @override
  Stream<void> get supportChanges => _support.stream;
  void announce() => _support.add(null);
  int flows = 0;
  @override
  void beginFlow() => flows++;
  final codes = <String>[];
  final submits = <(String, String)>[];
  int opens = 0;
  @override
  bool get supportsGameIdentityVerification => supported;
  @override
  Future<GameIdentityResult> requestVerificationCode(String handle) async {
    codes.add(handle);
    return code;
  }

  @override
  Future<GameIdentityResult> submitVerification(
    String handle,
    String contact,
  ) async {
    submits.add((handle, contact));
    return verify;
  }

  @override
  Future<bool> openRsiProfile() async {
    opens++;
    return opened;
  }
}

Widget _host(
  GameIdentityVerificationPort port, {
  String? initialHandle,
  VoidCallback? onVerified,
  Locale locale = const Locale('zh', 'CN'),
  double textScale = 1,
}) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    locale,
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      disableAnimations: true,
      textScaler: TextScaler.linear(textScale),
    ),
    child: child!,
  ),
  home: Builder(
    builder: (context) => Scaffold(
      body: TextButton(
        key: const Key('open'),
        onPressed: () => unawaited(
          showGameIdentityVerificationDialog(
            context,
            port,
            initialHandle: initialHandle,
            onVerified: onVerified,
          ),
        ),
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
}

Future<void> _primary(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('game-identity-primary')));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Finder get _notice => find.byKey(const Key('game-identity-notice'));

String _noticeText(WidgetTester tester) =>
    tester.widget<Text>(_notice).data ?? '';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final clipboard = <String>[];
  setUp(() {
    clipboard.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('panel', () {
    testWidgets('detected Handle is filled in and can still be edited', (
      tester,
    ) async {
      final port = _Port();
      await tester.pumpWidget(_host(port, initialHandle: 'Pilot_A'));
      await _open(tester);
      expect(find.text('Pilot_A'), findsOneWidget);
      expect(find.textContaining('已从游戏日志填入'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('game-identity-handle')),
        'Pilot_B',
      );
      await _primary(tester);
      expect(port.codes, ['Pilot_B']);
    });

    testWidgets('a bad Handle never reaches SCM', (tester) async {
      final port = _Port();
      await tester.pumpWidget(_host(port));
      await _open(tester);
      for (final bad in ['', 'ab', 'has space', 'bad/char']) {
        await tester.enterText(
          find.byKey(const Key('game-identity-handle')),
          bad,
        );
        await _primary(tester);
        expect(_noticeText(tester), contains('RSI Handle'));
      }
      expect(port.codes, isEmpty);
    });

    testWidgets('code is copied, counted down and the contact is checked', (
      tester,
    ) async {
      final port = _Port();
      await tester.pumpWidget(_host(port, initialHandle: 'Pilot_A'));
      await _open(tester);
      await _primary(tester);
      expect(find.text('SB-CODE-1'), findsOneWidget);
      expect(clipboard, ['SB-CODE-1']);
      expect(find.text('有效期 10 分 00 秒'), findsOneWidget);
      expect(find.textContaining('可能在 SCM 交易里显示给别人'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('game-identity-contact')),
        'short',
      );
      await _primary(tester);
      expect(port.submits, isEmpty);
      expect(_noticeText(tester), contains('7 到 256'));
      await tester.tap(find.byKey(const Key('game-identity-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets('acceptance closes the panel and reports once', (tester) async {
      final port = _Port();
      var verified = 0;
      await tester.pumpWidget(
        _host(port, initialHandle: 'Pilot_A', onVerified: () => verified++),
      );
      await _open(tester);
      await _primary(tester);
      await tester.enterText(
        find.byKey(const Key('game-identity-contact')),
        'pilot@example.test',
      );
      await _primary(tester);
      await tester.pumpAndSettle();
      expect(port.submits, [('Pilot_A', 'pilot@example.test')]);
      expect(verified, 1);
      expect(find.byKey(const Key('game-identity-panel')), findsNothing);
    });

    testWidgets('a rejection shows SCM wording and keeps what was typed', (
      tester,
    ) async {
      final port = _Port()
        ..verify = const GameIdentityResult(
          GameIdentityOutcome.rejected,
          message: 'SCM 原文：没有找到验证码',
        );
      var verified = 0;
      await tester.pumpWidget(
        _host(port, initialHandle: 'Pilot_A', onVerified: () => verified++),
      );
      await _open(tester);
      await _primary(tester);
      await tester.enterText(
        find.byKey(const Key('game-identity-contact')),
        'pilot@example.test',
      );
      await _primary(tester);
      expect(_noticeText(tester), 'SCM 原文：没有找到验证码');
      expect(find.text('pilot@example.test'), findsOneWidget);
      expect(verified, 0);
      await tester.tap(find.byKey(const Key('game-identity-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets('an unknown outcome claims neither success nor failure', (
      tester,
    ) async {
      final port = _Port()
        ..verify = const GameIdentityResult(GameIdentityOutcome.outcomeUnknown);
      var verified = 0;
      await tester.pumpWidget(
        _host(port, initialHandle: 'Pilot_A', onVerified: () => verified++),
      );
      await _open(tester);
      await _primary(tester);
      await tester.enterText(
        find.byKey(const Key('game-identity-contact')),
        'pilot@example.test',
      );
      await _primary(tester);
      expect(_noticeText(tester), contains('暂时无法确认验证结果'));
      expect(verified, 0);
      await tester.tap(find.byKey(const Key('game-identity-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets('an expired code blocks submitting until a new one', (
      tester,
    ) async {
      final port = _Port()
        ..code = const GameIdentityResult(
          GameIdentityOutcome.issued,
          verificationCode: 'SB-CODE-1',
          expiresInSeconds: 1,
        );
      await tester.pumpWidget(_host(port, initialHandle: 'Pilot_A'));
      await _open(tester);
      await _primary(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('验证码已过期'), findsOneWidget);
      expect(_noticeText(tester), contains('重新获取'));
      await tester.enterText(
        find.byKey(const Key('game-identity-contact')),
        'pilot@example.test',
      );
      await tester.tap(find.byKey(const Key('game-identity-primary')));
      await tester.pump();
      expect(port.submits, isEmpty);
      await tester.tap(find.byKey(const Key('game-identity-back')));
      await tester.pump();
      expect(find.byKey(const Key('game-identity-handle')), findsOneWidget);
      expect(find.text('Pilot_A'), findsOneWidget);
      await tester.tap(find.byKey(const Key('game-identity-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets('a browser failure is said plainly', (tester) async {
      final port = _Port()..opened = false;
      await tester.pumpWidget(_host(port, initialHandle: 'Pilot_A'));
      await _open(tester);
      await _primary(tester);
      await tester.tap(find.byKey(const Key('game-identity-open-rsi')));
      await tester.pump();
      await tester.pump();
      expect(port.opens, 1);
      expect(_noticeText(tester), contains('无法打开浏览器'));
      await tester.tap(find.byKey(const Key('game-identity-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets('no pending wording and no overflow in English at 2x', (
      tester,
    ) async {
      final port = _Port();
      await tester.pumpWidget(
        _host(
          port,
          initialHandle: 'Pilot_A',
          locale: const Locale('en', 'US'),
          textScale: 2,
        ),
      );
      await _open(tester);
      await _primary(tester);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('待确认'), findsNothing);
      await tester.tap(find.byKey(const Key('game-identity-cancel')));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('closing forgets the code and leaves the clipboard alone', (
    tester,
  ) async {
    final port = _Port();
    await tester.pumpWidget(_host(port, initialHandle: 'Pilot_A'));
    await _open(tester);
    expect(port.flows, 1);
    await _primary(tester);
    expect(clipboard, ['SB-CODE-1']);
    await tester.tap(find.byKey(const Key('game-identity-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('SB-CODE-1'), findsNothing);
    expect(clipboard, ['SB-CODE-1']);
    await _open(tester);
    expect(port.flows, 2);
    expect(find.text('SB-CODE-1'), findsNothing);
    await tester.tap(find.byKey(const Key('game-identity-cancel')));
    await tester.pumpAndSettle();
  });

  testWidgets('an open panel stops submitting when support goes away', (
    tester,
  ) async {
    final port = _Port();
    await tester.pumpWidget(_host(port, initialHandle: 'Pilot_A'));
    await _open(tester);
    port.supported = false;
    port.announce();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('game-identity-primary')));
    await tester.pump();
    expect(port.codes, isEmpty);
    expect(find.byKey(const Key('game-identity-panel')), findsOneWidget);
    await tester.tap(find.byKey(const Key('game-identity-cancel')));
    await tester.pumpAndSettle();
  });

  group('wire', () {
    late InMemoryBridgePair pair;
    late BridgeClientSession session;
    late StreamSubscription<BridgeEnvelope> incoming;
    final requests = <BridgeEnvelope>[];
    Map<String, Object?> Function(BridgeEnvelope) reply = (_) => const {};
    var state = 'signedIn';

    setUp(() {
      requests.clear();
      state = 'signedIn';
      pair = InMemoryBridgeConnection.createPair();
      session = BridgeClientSession(
        connection: pair.client,
        sessionGeneration: 1,
      )..acceptHostCapabilities([BridgeGameIdentityVerification.capability]);
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
            accountContext: BridgeAccountContext(
              environment: 'test',
              authority: 'scm',
              subject: 'synthetic',
            ),
            status: 'ok',
            payload: request.name == 'account.getCurrent'
                ? {'schemaVersion': 1, 'state': state}
                : reply(request),
          ),
        );
      });
    });
    tearDown(() async {
      await incoming.cancel();
      await session.close();
      await pair.host.close();
    });

    test(
      'sends trimmed fields for the current owner and decodes a code',
      () async {
        reply = (_) => {
          'schemaVersion': 1,
          'outcome': 'issued',
          'verificationCode': 'SB-1',
          'expiresInSeconds': 600,
        };
        final port = BridgeGameIdentityVerification(session)..beginFlow();
        final result = await port.requestVerificationCode('  Pilot_A ');
        expect(result.outcome, GameIdentityOutcome.issued);
        expect(result.verificationCode, 'SB-1');
        final sent = requests.last;
        expect(sent.name, 'account.gameIdentity.requestCode');
        expect(sent.accountContext?.subject, 'synthetic');
        expect(sent.payload, {'schemaVersion': 1, 'gameName': 'Pilot_A'});
      },
    );

    test('a verified outcome is never accepted for a code request', () async {
      reply = (_) => {'schemaVersion': 1, 'outcome': 'verified'};
      final port = BridgeGameIdentityVerification(session)..beginFlow();
      expect(
        (await port.requestVerificationCode('Pilot_A')).outcome,
        GameIdentityOutcome.unavailable,
      );
    });

    test('a malformed verify reply is unknown, never a failure', () async {
      reply = (_) => {'schemaVersion': 2, 'outcome': 'verified'};
      final port = BridgeGameIdentityVerification(session)..beginFlow();
      expect(
        (await port.submitVerification('Pilot_A', 'contact-1')).outcome,
        GameIdentityOutcome.outcomeUnknown,
      );
    });

    test(
      'a flow never continues on another session of the same account',
      () async {
        reply = (_) => {'schemaVersion': 1, 'outcome': 'rejected'};
        final port = BridgeGameIdentityVerification(session)..beginFlow();
        await port.requestVerificationCode('Pilot_A');
        final sent = requests.length;
        session.advanceGeneration(2);
        expect(
          (await port.submitVerification('Pilot_A', 'contact-1')).outcome,
          GameIdentityOutcome.unavailable,
        );
        expect(
          requests.skip(sent).map((r) => r.name),
          isNot(contains('account.gameIdentity.verify')),
        );
      },
    );

    test(
      'a generation change while reading the owner stops the send',
      () async {
        reply = (_) => {'schemaVersion': 1, 'outcome': 'rejected'};
        final port = BridgeGameIdentityVerification(session)..beginFlow();
        final pending = port.submitVerification('Pilot_A', 'contact-1');
        session.advanceGeneration(2);
        expect((await pending).outcome, GameIdentityOutcome.unavailable);
        expect(
          requests.map((r) => r.name),
          isNot(contains('account.gameIdentity.verify')),
        );
      },
    );

    test('a signed-out host sends nothing', () async {
      state = 'signedOut';
      final port = BridgeGameIdentityVerification(session)..beginFlow();
      expect(
        (await port.submitVerification('Pilot_A', 'contact-1')).outcome,
        GameIdentityOutcome.unavailable,
      );
      expect(requests.map((r) => r.name), ['account.getCurrent']);
    });

    test('only an explicit opened flag counts', () async {
      reply = (_) => {'schemaVersion': 1, 'opened': true};
      final port = BridgeGameIdentityVerification(session)..beginFlow();
      expect(await port.openRsiProfile(), isTrue);
      expect(requests.last.payload, {'schemaVersion': 1});
      reply = (_) => {'schemaVersion': 1};
      expect(await port.openRsiProfile(), isFalse);
    });

    test('capability gates support', () {
      final without = BridgeClientSession(
        connection: InMemoryBridgeConnection.createPair().client,
        sessionGeneration: 1,
      );
      expect(
        BridgeGameIdentityVerification(without)
            .supportsGameIdentityVerification,
        isFalse,
      );
    });
  });

  group('identity card', () {
    Future<AccountModule> pumpPage(
      WidgetTester tester,
      AccountReviewState state,
      _Port port,
    ) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final module = createAccountModule(
        InMemoryAccountAdapter.forReview(state),
      );
      addTearDown(module.dispose);
      await module.initialize();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStringsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            const Locale('zh', 'CN'),
          ),
          home: Scaffold(
            body: AccountPage(module: module, gameIdentity: port),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return module;
    }

    const action = Key('account-verify-game-identity');

    testWidgets('an unverified account says so and offers the panel', (
      tester,
    ) async {
      await pumpPage(tester, AccountReviewState.verificationRequired, _Port());
      expect(find.textContaining('还没有验证游戏身份'), findsOneWidget);
      expect(find.text('暂时无法确认 RSI 身份状态。'), findsNothing);
      await tester.ensureVisible(find.byKey(action));
      await tester.tap(find.byKey(action));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('game-identity-panel')), findsOneWidget);
      await tester.tap(find.byKey(const Key('game-identity-cancel')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a verified account has no verify action', (tester) async {
      await pumpPage(tester, AccountReviewState.signedIn, _Port());
      expect(find.byKey(action), findsNothing);
    });

    testWidgets('the action follows the Host capability', (tester) async {
      final port = _Port()..supported = false;
      await pumpPage(tester, AccountReviewState.verificationRequired, port);
      expect(find.byKey(action), findsNothing);
      expect(find.textContaining('还没有验证游戏身份'), findsOneWidget);
      port.supported = true;
      port.announce();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(action), findsOneWidget);
    });

    testWidgets('losing the capability does not close an open panel', (
      tester,
    ) async {
      final port = _Port();
      await pumpPage(tester, AccountReviewState.verificationRequired, port);
      await tester.ensureVisible(find.byKey(action));
      await tester.tap(find.byKey(action));
      await tester.pumpAndSettle();
      port.supported = false;
      port.announce();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('game-identity-panel')), findsOneWidget);
      await tester.tap(find.byKey(const Key('game-identity-cancel')));
      await tester.pumpAndSettle();
    });
  });

  test('the Host states decode and keep sensitive writes off', () {
    for (final entry in {
      'verificationRequired': AccountIdentityState.verificationRequired,
      'verificationPending': AccountIdentityState.verificationPending,
    }.entries) {
      final identity = AccountPayloadDecoder.identity({
        'schemaVersion': 1,
        'state': entry.key,
        'sensitiveWritesAllowed': false,
        'scmBindingState': 'unknown',
      });
      expect(identity.state, entry.value);
      expect(identity.sensitiveWritesAllowed, isFalse);
    }
    expect(
      () => AccountPayloadDecoder.identity({
        'schemaVersion': 1,
        'state': 'verificationRequired',
        'sensitiveWritesAllowed': true,
      }),
      throwsA(anything),
    );
  });

  test('validators match the Host rule', () {
    expect(isValidGameIdentityHandle('Pilot_A.1-b'), isTrue);
    expect(isValidGameIdentityHandle(' ab '), isFalse);
    expect(isValidGameIdentityHandle('a' * 65), isFalse);
    expect(isValidGameIdentityContact('1234567'), isTrue);
    expect(isValidGameIdentityContact(' 123456 '), isFalse);
    expect(isValidGameIdentityContact('a' * 257), isFalse);
  });
}
