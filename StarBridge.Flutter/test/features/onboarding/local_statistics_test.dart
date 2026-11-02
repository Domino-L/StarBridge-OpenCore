import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_local_statistics_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/local_statistics_controller.dart';
import 'package:starbridge_flutter/features/onboarding/local_statistics_port.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';

import 'onboarding_page_test.dart' show pumpSetup;
import 'onboarding_test_support.dart';
import 'local_statistics_test_support.dart';

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
  test(
    'strict unknown, saved and inactive projections never imply consent',
    () {
      expect(LocalStatisticsWire.parse(statisticsWire()).choiceSaved, false);
      expect(
        LocalStatisticsWire.parse(
          statisticsWire(state: 'saved', consent: 'declined'),
        ).choiceSaved,
        true,
      );
      expect(
        LocalStatisticsWire.parse(
          statisticsWire(state: 'inactive', key: null, seconds: null),
        ).canChoose,
        false,
      );
      for (final raw in [
        {...statisticsWire()}..remove('consent'),
        {...statisticsWire(), 'profileId': 'private'},
        {...statisticsWire(), 'schemaVersion': true},
        {...statisticsWire(), 'state': 'ready'},
        {...statisticsWire(), 'choiceKey': 'private/path'},
        {...statisticsWire(), 'recording': 'true'},
        {...statisticsWire(), 'savedSeconds': -1},
        {...statisticsWire(), 'savedSeconds': 1.5},
        statisticsWire(state: 'saved'),
        statisticsWire(recording: true),
        statisticsWire(seconds: 1),
        statisticsWire(state: 'inactive'),
        statisticsWire(
          state: 'retryRequired',
          consent: 'declined',
          recording: true,
        ),
        statisticsWire(state: 'saved', consent: 'declined', recording: true),
      ]) {
        expect(() => LocalStatisticsWire.parse(raw), throwsFormatException);
      }
    },
  );
  for (final allowed in [true, false]) {
    test(
      'only explicit ${allowed ? 'allow' : 'decline'} can persist; reread clears drafts',
      () async {
        final port = FakeStatisticsPort();
        final c = LocalStatisticsController(port);
        addTearDown(c.dispose);
        addTearDown(port.close);
        await c.refresh();
        expect(c.value.selected, null);
        expect(c.value.canConfirm, false);
        await c.confirm();
        expect(port.confirmations, 0);
        c.select(allowed);
        await c.refresh();
        expect(c.value.selected, null);
        c.select(allowed);
        await c.confirm();
        expect(c.value.snapshot.choiceSaved, true);
        expect(
          c.value.snapshot.consent,
          allowed
              ? LocalStatisticsConsent.allowed
              : LocalStatisticsConsent.declined,
        );
        expect(c.value.selected, null);
        expect(port.confirmations, 1);
      },
    );
  }
  test(
    'failed or mismatched save cannot preserve selection or claim ready',
    () async {
      final port = FakeStatisticsPort();
      final c = LocalStatisticsController(port);
      addTearDown(c.dispose);
      addTearDown(port.close);
      await c.refresh();
      c.select(true);
      port.failConfirm = true;
      await c.confirm();
      expect(c.value.error, true);
      expect(c.value.selected, null);
      expect(c.value.snapshot.choiceSaved, false);
      port.failConfirm = false;
      await c.refresh();
      c.select(true);
      port.pendingConfirm = Future.value(
        LocalStatisticsWire.parse(
          statisticsWire(state: 'saved', consent: 'declined'),
        ),
      );
      await c.confirm();
      expect(c.value.error, true);
      port.failRead = true;
      await c.refresh();
      expect(c.value.snapshot.canChoose, false);
    },
  );
  test(
    'invalidations drain same operation and reject late confirmation',
    () async {
      final port = FakeStatisticsPort();
      final c = LocalStatisticsController(port);
      addTearDown(c.dispose);
      addTearDown(port.close);
      await c.refresh();
      c.select(true);
      final pending = Completer<LocalStatisticsSnapshot>();
      port.pendingConfirm = pending.future;
      final write = c.confirm();
      port.events.add(null);
      expect(c.value.busy, true);
      expect(c.value.selected, null);
      await c.confirm();
      expect(port.confirmations, 1);
      expect(port.reads, 1);
      pending.complete(
        LocalStatisticsWire.parse(
          statisticsWire(state: 'saved', consent: 'allowed'),
        ),
      );
      await write;
      await Future<void>.delayed(Duration.zero);
      expect(port.reads, 2);
      expect(c.value.snapshot.choiceSaved, false);
    },
  );
  test(
    'missing capability emits no request; device exceptions stay exact',
    () async {
      final f = StatisticsBridgeFixture(capabilities: false);
      addTearDown(f.close);
      expect((await f.adapter.read()).canChoose, false);
      expect(f.requests, isEmpty);
      for (final name in [
        'onboarding.localStatistics.read',
        'onboarding.localStatistics.confirm',
      ]) {
        expect(
          () => BridgeRequestPolicy.requireAccountContext(name, null),
          returnsNormally,
        );
      }
      expect(
        () => BridgeRequestPolicy.requireAccountContext(
          'onboarding.localStatistics.reset',
          null,
        ),
        throwsA(isA<BridgeAccountContextRequiredException>()),
      );
      expect(
        () => BridgeRequestPolicy.requireAccountContext('friends.read', null),
        throwsA(isA<BridgeAccountContextRequiredException>()),
      );
    },
  );
  test(
    'real Adapter sends only the current opaque key and explicit boolean',
    () async {
      final f = StatisticsBridgeFixture();
      addTearDown(f.close);
      final read = await f.adapter.read();
      final saved = await f.adapter.confirm(read.choiceKey!, false);
      expect(saved.consent, LocalStatisticsConsent.declined);
      expect(f.requests.last.accountContext, null);
      expect(f.requests.last.payload, {
        'schemaVersion': 1,
        'choiceKey': read.choiceKey,
        'allowed': false,
      });
      expect(() => f.adapter.confirm(read.choiceKey!, true), throwsStateError);
    },
  );
  test(
    'late invalidated reply, malformed reply and new generation revoke tickets',
    () async {
      final f = StatisticsBridgeFixture();
      addTearDown(f.close);
      final entered = Completer<BridgeEnvelope>();
      f.onRequest = (request) async {
        entered.complete(request);
      };
      final subscription = f.adapter.invalidations.listen((_) {});
      addTearDown(subscription.cancel);
      final read = f.adapter.read();
      final request = await entered.future;
      await f.pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          sequence: 1,
          name: 'account.changed',
          correlationId: 'synthetic-event',
          sessionGeneration: 3,
          status: 'ok',
          payload: const {},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final rejected = expectLater(read, throwsStateError);
      await f.respond(request);
      await rejected;
      f.onRequest = null;
      f.payload = {...statisticsWire(), 'consent': true};
      await expectLater(f.adapter.read(), throwsFormatException);
      f.payload = null;
      final value = await f.adapter.read();
      f.session.advanceGeneration(4);
      expect(() => f.adapter.confirm(value.choiceKey!, true), throwsStateError);
    },
  );
  test('transport failure consumes prior observation without replay', () async {
    final f = StatisticsBridgeFixture();
    addTearDown(f.close);
    final value = await f.adapter.read();
    await f.pair.host.close();
    await expectLater(
      f.adapter.confirm(value.choiceKey!, true),
      throwsA(isA<Object>()),
    );
    expect(() => f.adapter.confirm(value.choiceKey!, true), throwsStateError);
  });
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    testWidgets(
      'statistics fits 320 width and 160 percent ${locale.toLanguageTag()}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = FakeStatisticsPort();
        final c = LocalStatisticsController(port);
        addTearDown(c.dispose);
        addTearDown(port.close);
        await pumpSetup(
          tester,
          step: OnboardingStep.local,
          mode: OnboardingMode.local,
          locale: locale,
          scale: 1.6,
          observation: facts(confirmed: true, localReady: false),
          localStatistics: c,
        );
        expect(port.confirmations, 0);
        expect(c.value.selected, null);
        expect(tester.takeException(), null);
        await tester.scrollUntilVisible(
          find.byKey(const Key('statistics-decline')),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const Key('statistics-decline')));
        await tester.pumpAndSettle();
        expect(c.value.selected, false);
        expect(tester.takeException(), null);
      },
    );
  }
  testWidgets(
    'saved decline does not enable listening, sharing or aggregate local readiness',
    (tester) async {
      final port = FakeStatisticsPort();
      final c = LocalStatisticsController(port);
      addTearDown(c.dispose);
      addTearDown(port.close);
      final main = await pumpSetup(
        tester,
        step: OnboardingStep.local,
        mode: OnboardingMode.local,
        observation: facts(confirmed: true, localReady: false),
        localStatistics: c,
      );
      c.select(false);
      await c.confirm();
      await tester.pumpAndSettle();
      expect(c.value.snapshot.choiceSaved, true);
      expect(main.value.facts.localSettingsReady, false);
      expect(main.canContinue, false);
      expect(main.value.step, OnboardingStep.local);
    },
  );
  testWidgets(
    'confirmation blocks back and close until the same operation exits',
    (tester) async {
      final port = FakeStatisticsPort();
      final c = LocalStatisticsController(port);
      addTearDown(c.dispose);
      addTearDown(port.close);
      var closed = 0;
      await pumpSetup(
        tester,
        step: OnboardingStep.local,
        mode: OnboardingMode.local,
        observation: facts(confirmed: true, localReady: false),
        localStatistics: c,
        onClose: () {
          closed++;
        },
      );
      c.select(true);
      final pending = Completer<LocalStatisticsSnapshot>();
      port.pendingConfirm = pending.future;
      final operation = c.confirm();
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('onboarding-back')))
            .onPressed,
        null,
      );
      await tester.tap(find.byKey(const Key('onboarding-close')));
      tester
          .widget<PopScope>(
            find.byWidgetPredicate((widget) => widget is PopScope).first,
          )
          .onPopInvokedWithResult
          ?.call(false, null);
      await tester.pump();
      expect(closed, 0);
      pending.complete(
        LocalStatisticsWire.parse(
          statisticsWire(state: 'saved', consent: 'allowed'),
        ),
      );
      await operation;
      await tester.pumpAndSettle();
      expect(closed, 0);
    },
  );
  testWidgets('preview statistics-choice-dark', (tester) async {
    tester.view.physicalSize = const Size(1280, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = FakeStatisticsPort();
    final c = LocalStatisticsController(port);
    addTearDown(c.dispose);
    addTearDown(port.close);
    await pumpSetup(
      tester,
      step: OnboardingStep.local,
      mode: OnboardingMode.local,
      observation: facts(confirmed: true, localReady: false),
      localStatistics: c,
    );
      await tester.ensureVisible(find.byKey(const Key('statistics-confirm')));
      await tester.pumpAndSettle();
    if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
      await expectLater(
        find.byKey(const Key('onboarding-capture')),
        matchesGoldenFile('goldens/statistics-choice-dark.png'),
      );
    }
  });
}
