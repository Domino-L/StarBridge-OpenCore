import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_onboarding_profile_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_controller.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_copy.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_page.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_profile_controller.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_profile_panel.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_profile_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'onboarding_test_support.dart';

const _rsi =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const _owner = BridgeAccountContext(
  environment: 'synthetic',
  authority: 'scm',
  subject: 'owner',
);

final class FakeProfilePort implements OnboardingProfilePort {
  FakeProfilePort({this.snapshot = _ready});
  static const _ready = OnboardingProfileSnapshot(
    callSign: 'Pilot Example',
    avatarImageData: _rsi,
    canRename: true,
    canOpenRsi: true,
  );
  OnboardingProfileSnapshot? snapshot;
  final changes = StreamController<void>.broadcast();
  int reads = 0, opens = 0;
  final saves = <(String, String)>[];
  OnboardingProfileSaveException? failure;
  bool openFails = false;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<OnboardingProfileSnapshot?> read() async {
    reads++;
    return snapshot;
  }

  @override
  Future<String> saveCallSign(String expected, String next) async {
    saves.add((expected, next));
    if (failure != null) throw failure!;
    return next;
  }

  @override
  Future<void> openRsiProfile() async {
    opens++;
    if (openFails) throw StateError('synthetic');
  }
}

Widget _app(Widget child, {Locale locale = const Locale('zh', 'CN')}) =>
    MaterialApp(
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        locale,
      ),
      locale: locale,
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: child),
    );

Future<OnboardingProfileController> _ready(FakeProfilePort port) async {
  final controller = OnboardingProfileController(port);
  addTearDown(controller.dispose);
  await controller.activate();
  return controller;
}

Future<void> _pumpPanel(
  WidgetTester tester,
  OnboardingProfileController controller,
) async {
  const copy = OnboardingCopy(Locale('zh', 'CN'));
  await tester.pumpWidget(
    _app(
      SingleChildScrollView(
        child: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => OnboardingProfilePanel(
            copy: copy,
            controller: controller,
            handle: 'Pilot-Example',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

String _note(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('onboarding-profile-note'))).data!;

class _ProfileBridge {
  _ProfileBridge({bool rename = true}) {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 3,
    );
    session.acceptHostCapabilities([
      if (rename) 'account.callSign',
      'helpSupport.openRsiProfileSettings',
    ]);
    adapter = BridgeOnboardingProfileAdapter(session);
    subscription = pair.host.incoming.listen((request) async {
      requests.add(request);
      final reply = replies[request.name]?.call(request);
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: reply?.$3 == null ? 'ok' : 'error',
          error: reply?.$3 == null
              ? null
              : BridgeErrorBody(
                  code: reply!.$3!,
                  message: 'Synthetic failure.',
                  retryable: false,
                ),
          accountContext: reply?.$2,
          payload: reply?.$1 ?? const {'schemaVersion': 1},
        ),
      );
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final BridgeOnboardingProfileAdapter adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  final replies =
      <
        String,
        (Map<String, Object?>, BridgeAccountContext?, String?) Function(
          BridgeEnvelope,
        )
      >{};
  void signedIn() {
    replies['account.getCurrent'] = (_) => (
      {'schemaVersion': 1, 'state': 'signedIn', 'displayName': 'Pilot Example'},
      _owner,
      null,
    );
    replies['account.readAvatar'] = (_) => (
      {
        'schemaVersion': 1,
        'imageData': _rsi,
        'callSign': 'Pilot Example',
        'revision': 3,
      },
      _owner,
      null,
    );
  }

  Future<void> close() async {
    adapter.dispose();
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}

void main() {
  setUpAll(() async {
    for (final font in <String, String>{
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Saira': 'assets/fonts/Saira-VF.ttf',
      'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  group('bridge adapter', () {
    test(
      'no installed SCM account means no panel and no account read',
      () async {
        for (final state in ['signedOut', 'legacySignedIn']) {
          final bridge = _ProfileBridge();
          bridge.replies['account.getCurrent'] = (_) => (
            {'schemaVersion': 1, 'state': state},
            state == 'signedOut' ? null : _owner,
            null,
          );
          expect(await bridge.adapter.read(), isNull);
          expect(bridge.requests.map((r) => r.name), ['account.getCurrent']);
          await bridge.close();
        }
      },
    );

    test(
      'reads the RSI avatar and nickname of the installed account',
      () async {
        final bridge = _ProfileBridge();
        bridge.signedIn();
        final snapshot = (await bridge.adapter.read())!;
        expect(snapshot.callSign, 'Pilot Example');
        expect(snapshot.avatarImageData, _rsi);
        expect(snapshot.canRename && snapshot.canOpenRsi, isTrue);
        final avatar = bridge.requests.last;
        expect(avatar.name, 'account.readAvatar');
        expect(avatar.accountContext?.subject, 'owner');
        await bridge.close();
      },
    );

    test('rename sends the read name as the expected value', () async {
      final bridge = _ProfileBridge();
      bridge.signedIn();
      bridge.replies['account.updateCallSign'] = (request) => (
        {'schemaVersion': 1, 'callSign': request.payload['callSign']},
        _owner,
        null,
      );
      await bridge.adapter.read();
      expect(
        await bridge.adapter.saveCallSign('Pilot Example', 'Night Pilot'),
        'Night Pilot',
      );
      final rename = bridge.requests.last;
      expect(rename.name, 'account.updateCallSign');
      expect(rename.accountContext?.subject, 'owner');
      expect(rename.payload, {
        'schemaVersion': 1,
        'expectedCallSign': 'Pilot Example',
        'callSign': 'Night Pilot',
      });
      await bridge.close();
    });

    test(
      'Host failures map to copy keys; conflicts ask for a reread',
      () async {
        for (final (code, key, conflict) in [
          ('account.callsign_conflict', 'profile.save.conflict', true),
          ('account.callsign_unconfirmed', 'profile.save.unconfirmed', true),
          ('account.callsign_invalid', 'profile.save.invalid', false),
          ('personal_profile.write_forbidden', 'profile.save.forbidden', false),
          ('account.callsign_unavailable', 'profile.save.failed', false),
        ]) {
          final bridge = _ProfileBridge();
          bridge.signedIn();
          bridge.replies['account.updateCallSign'] = (_) =>
              (const {'schemaVersion': 1}, _owner, code);
          await bridge.adapter.read();
          await expectLater(
            bridge.adapter.saveCallSign('Pilot Example', 'Night Pilot'),
            throwsA(
              isA<OnboardingProfileSaveException>()
                  .having((e) => e.key, 'key', key)
                  .having((e) => e.conflict, 'conflict', conflict),
            ),
          );
          await bridge.close();
        }
      },
    );

    test('without the rename capability nothing is sent', () async {
      final bridge = _ProfileBridge(rename: false);
      bridge.signedIn();
      expect((await bridge.adapter.read())!.canRename, isFalse);
      final sent = bridge.requests.length;
      await expectLater(
        bridge.adapter.saveCallSign('Pilot Example', 'Night Pilot'),
        throwsA(isA<OnboardingProfileSaveException>()),
      );
      expect(bridge.requests.length, sent);
      await bridge.close();
    });
  });

  group('controller', () {
    test('reads once on activation and never renames by itself', () async {
      final port = FakeProfilePort();
      final controller = await _ready(port);
      await controller.activate();
      expect(port.reads, 1);
      expect(controller.value.visible, isTrue);
      expect(controller.value.canSave, isFalse);
      controller.edit('Night Pilot');
      expect(controller.value.dirty && controller.value.canSave, isTrue);
      expect(port.saves, isEmpty);
    });

    test('a failed rename keeps the name and is never resent', () async {
      final port = FakeProfilePort()
        ..failure = const OnboardingProfileSaveException('profile.save.failed');
      final controller = await _ready(port);
      controller.edit('Night Pilot');
      await controller.save();
      expect(port.saves, [('Pilot Example', 'Night Pilot')]);
      expect(controller.value.failureKey, 'profile.save.failed');
      expect(controller.value.snapshot!.callSign, 'Pilot Example');
      expect(controller.value.draft, 'Night Pilot');
      expect(port.saves.length, 1);
    });

    test('a conflict rereads the real name and keeps the draft', () async {
      final port = FakeProfilePort()
        ..failure = const OnboardingProfileSaveException(
          'profile.save.conflict',
          conflict: true,
        );
      final controller = await _ready(port);
      controller.edit('Night Pilot');
      port.snapshot = const OnboardingProfileSnapshot(
        callSign: 'Changed Elsewhere',
        canRename: true,
      );
      await controller.save();
      expect(port.reads, 2);
      expect(controller.value.snapshot!.callSign, 'Changed Elsewhere');
      expect(controller.value.draft, 'Night Pilot');
      expect(controller.value.failureKey, 'profile.save.conflict');
    });

    test('invalid names cannot be saved', () async {
      final controller = await _ready(FakeProfilePort());
      for (final bad in ['', '   ', 'x' * 33, 'a\u0007b']) {
        controller.edit(bad);
        expect(controller.value.canSave, isFalse, reason: bad);
      }
    });

    test('no account installed hides the panel', () async {
      final controller = await _ready(FakeProfilePort(snapshot: null));
      expect(controller.value.load, OnboardingProfileLoad.absent);
      expect(controller.value.visible, isFalse);
    });
  });

  group('panel', () {
    testWidgets('unsaved, saved and RSI link states', (tester) async {
      final port = FakeProfilePort();
      final controller = await _ready(port);
      await _pumpPanel(tester, controller);
      expect(find.text('来自 RSI 账号'), findsOneWidget);
      expect(
        find.textContaining('Pilot-Example', findRichText: true),
        findsOneWidget,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('onboarding-profile-save')),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const Key('onboarding-profile-name')),
        'Night Pilot',
      );
      await tester.pump();
      expect(find.byKey(const Key('profile-status-unsaved')), findsOneWidget);
      expect(_note(tester), contains('直接进入会保留原昵称'));
      await tester.tap(find.byKey(const Key('onboarding-profile-save')));
      await tester.pumpAndSettle();
      expect(port.saves, [('Pilot Example', 'Night Pilot')]);
      expect(find.byKey(const Key('profile-status-saved')), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding-profile-open-rsi')));
      await tester.pump();
      expect(port.opens, 1);
    });

    testWidgets('failure shows the kept name and a retry', (tester) async {
      final port = FakeProfilePort()
        ..failure = const OnboardingProfileSaveException('profile.save.failed');
      final controller = await _ready(port);
      await _pumpPanel(tester, controller);
      await tester.enterText(
        find.byKey(const Key('onboarding-profile-name')),
        'Night Pilot',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('onboarding-profile-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-status-failed')), findsOneWidget);
      expect(_note(tester), contains('仍是“Pilot Example”'));
      expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);
    });

    testWidgets('rename unavailable keeps the field read-only', (tester) async {
      final controller = await _ready(
        FakeProfilePort(
          snapshot: const OnboardingProfileSnapshot(callSign: 'Pilot Example'),
        ),
      );
      await _pumpPanel(tester, controller);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('onboarding-profile-name')))
            .enabled,
        isFalse,
      );
      expect(
        find.byKey(const Key('onboarding-profile-open-rsi')),
        findsNothing,
      );
      expect(_note(tester), contains('个人资料页修改'));
    });

    test('profile copy exists in three locales', () {
      for (final locale in const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('en', 'US'),
      ]) {
        final copy = OnboardingCopy(locale);
        for (final key in [
          'done.title',
          'done.lead.online',
          'done.lead.local',
          'enterApp',
          'profile.title',
          'profile.keptName',
          'profile.save.unconfirmed',
          'results.expand',
        ]) {
          expect(copy.text(key), isNotEmpty);
        }
      }
    });
  });

  testWidgets('finish page shows the profile only after an online save', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = FakeOnboardingPort(facts(confirmed: true));
    await fake.execute(
      OnboardingAction.applyMode,
      const OnboardingCheckpoint(mode: OnboardingMode.online),
    );
    fake.restored = OnboardingCheckpoint(
      step: OnboardingStep.summary,
      mode: OnboardingMode.online,
      sourceKey: fake.facts.sourceKey,
      evidenceKey: fake.facts.evidenceKey,
    );
    final controller = OnboardingController(fake);
    addTearDown(controller.dispose);
    final port = FakeProfilePort();
    final profile = OnboardingProfileController(port);
    addTearDown(profile.dispose);
    await tester.pumpWidget(
      _app(
        OnboardingPage(
          controller: controller,
          onClose: () {},
          profile: profile,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(port.reads, 0, reason: 'nothing is read before the save');
    expect(find.byKey(const Key('onboarding-profile-panel')), findsNothing);
    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pumpAndSettle();
    expect(controller.value.completed, isTrue);
    expect(port.reads, 1);
    expect(find.byKey(const Key('onboarding-profile-panel')), findsOneWidget);
    expect(find.text('欢迎来到星海舰桥'), findsOneWidget);
    expect(find.text('进入星海舰桥'), findsOneWidget);
    expect(find.byKey(const Key('summary-mode')), findsNothing);
    if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
      await expectLater(
        find.byType(OnboardingPage),
        matchesGoldenFile('goldens/finish-profile-dark.png'),
      );
    }
    await tester.tap(find.byKey(const Key('onboarding-results-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('summary-mode')), findsOneWidget);
    expect(port.saves, isEmpty);
  });
}
