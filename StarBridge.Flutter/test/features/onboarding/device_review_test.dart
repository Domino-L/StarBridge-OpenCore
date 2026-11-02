import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_device_review_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/device_review_controller.dart';
import 'package:starbridge_flutter/features/onboarding/device_review_port.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import 'onboarding_page_test.dart' show pumpSetup;
import 'onboarding_test_support.dart';
import 'device_review_test_support.dart';

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
  test('strict projection supports choicesRequired but never invents a review ticket', () {
    final raw = deviceWire(state: 'choicesRequired', key: null);
    (raw['application']! as Map<String, Object?>)['startupChoiceMade'] = false;
    final value = DeviceReviewWire.parse(raw);
    expect(value.canReview, false);
    expect(
      () =>
          value.sections[DeviceReviewSection.application]!['launchAtStartup'] =
              true,
      throwsUnsupportedError,
    );
  });
  test('missing, extra, malformed and inconsistent fields fail closed', () {
    for (final field in deviceWire().keys) {
      expect(
        () => DeviceReviewWire.parse(deviceWire()..remove(field)),
        throwsFormatException,
      );
    }
    for (final changes in [
      <String, Object?>{'schemaVersion': 1.0},
      {'state': 'ready'},
      {'reviewKey': 'C:/private/Game.log'},
      {'reviewKey': null},
      {'unexpected': true},
      {'application': null},
      {
        'notifications': {'inAppEnabled': true},
      },
    ]) {
      expect(
        () => DeviceReviewWire.parse({...deviceWire(), ...changes}),
        throwsFormatException,
      );
    }
    for (final change in [
      <String, Object?>{'hotkeyBinding': 'private/path'},
      {'opacity': double.nan},
      {'opacity': 1.2},
      {'hotkeyEnabled': 'true'},
      {'renderMode': 'browser'},
    ]) {
      final raw = deviceWire();
      (raw['overlay']! as Map<String, Object?>).addAll(change);
      expect(() => DeviceReviewWire.parse(raw), throwsFormatException);
    }
  });
  test('four explicit checks are required and editing erases presentation acknowledgements', () async {
    final port = FakeDeviceReviewPort();
    final controller = DeviceReviewController(port);
    addTearDown(controller.dispose);
    addTearDown(port.close);
    await controller.refresh();
    expect(controller.value.canConfirm, false);
    for (final section in DeviceReviewSection.values) {
      controller.check(section, true);
    }
    expect(controller.value.canConfirm, true);
    var opened = 0;
    await controller.edit(DeviceReviewSection.application, (_) async {
      opened++;
    });
    expect(opened, 1);
    expect(controller.value.checked, isEmpty);
    await controller.confirm();
    expect(port.confirmations, 0);
    for (final section in DeviceReviewSection.values) {
      controller.check(section, true);
    }
    await controller.confirm();
    expect(port.confirmations, 1);
    expect(controller.value.snapshot.state, DeviceReviewState.reviewed);
  });
  test(
    'unknown confirmation and failed reread do not retain checks or readiness',
    () async {
      final port = FakeDeviceReviewPort();
      final c = DeviceReviewController(port);
      addTearDown(c.dispose);
      addTearDown(port.close);
      await c.refresh();
      for (final section in DeviceReviewSection.values) {
        c.check(section, true);
      }
      port.onConfirm = () async => DeviceReviewWire.parse(deviceWire());
      await c.confirm();
      expect(c.value.error, true);
      expect(c.value.canConfirm, false);
      port.fail = true;
      await c.refresh();
      expect(c.value.snapshot.canReview, false);
      expect(c.value.checked, isEmpty);
    },
  );
  test('invalidation drains the same read before fresh observation; dispose rejects late result', () async {
    final port = FakeDeviceReviewPort();
    final c = DeviceReviewController(port);
    addTearDown(port.close);
    final blocked = Completer<DeviceReviewSnapshot>();
    port.onRead = () => blocked.future;
    final read = c.refresh();
    port.events.add(null);
    expect(port.reads, 1);
    expect(c.value.snapshot.canReview, false);
    port.onRead = null;
    blocked.complete(port.snapshot);
    await read;
    await Future<void>.delayed(Duration.zero);
    expect(port.reads, 2);
    expect(c.value.checked, isEmpty);
    final late = Completer<DeviceReviewSnapshot>();
    port.onRead = () => late.future;
    final pending = c.refresh();
    c.dispose();
    late.complete(port.snapshot);
    await pending;
  });
  test('missing capability sends no request; exact review exemptions do not authorize business', () async {
    final f = DeviceBridgeFixture(capabilities: false);
    addTearDown(f.close);
    expect((await f.adapter.read()).canReview, false);
    expect(f.requests, isEmpty);
    expect(
      () => f.adapter.confirm(
        '11111111111111111111111111111111',
        DeviceReviewSection.values.toSet(),
      ),
      throwsStateError,
    );
    for (final name in [
      'onboarding.deviceReview.read',
      'onboarding.deviceReview.confirm',
    ]) {
      expect(
        () => BridgeRequestPolicy.requireAccountContext(name, null),
        returnsNormally,
      );
    }
    expect(
      () => BridgeRequestPolicy.requireAccountContext(
        'onboarding.deviceReview.delete',
        null,
      ),
      throwsA(isA<BridgeAccountContextRequiredException>()),
    );
  });
  test('real bridge adapter sends only current opaque key and four sections without identity', () async {
    final f = DeviceBridgeFixture();
    addTearDown(f.close);
    final value = await f.adapter.read();
    await f.adapter.confirm(
      value.reviewKey!,
      DeviceReviewSection.values.toSet(),
    );
    final request = f.requests.last;
    expect(request.accountContext, null);
    expect(
      request.payload.keys,
      unorderedEquals(['schemaVersion', 'reviewKey', 'reviewedSections']),
    );
    expect(request.payload.toString(), isNot(contains('Handle')));
    expect(
      () => f.adapter.confirm(
        value.reviewKey!,
        DeviceReviewSection.values.toSet(),
      ),
      throwsStateError,
    );
  });
  test(
    'malformed reply and settings invalidation revoke old bridge observation',
    () async {
      final f = DeviceBridgeFixture();
      addTearDown(f.close);
      final events = f.adapter.invalidations.listen((_) {});
      addTearDown(events.cancel);
      final value = await f.adapter.read();
      await f.pair.host.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'overlay.changed',
          sessionGeneration: 3,
          sequence: 1,
          payload: {},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        () => f.adapter.confirm(
          value.reviewKey!,
          DeviceReviewSection.values.toSet(),
        ),
        throwsStateError,
      );
      f.payload = {};
      await expectLater(f.adapter.read(), throwsFormatException);
      expect(
        () => f.adapter.confirm(
          value.reviewKey!,
          DeviceReviewSection.values.toSet(),
        ),
        throwsStateError,
      );
    },
  );
  testWidgets(
    'device confirmation cannot advance overall local setup or enable collection',
    (tester) async {
      final port = FakeDeviceReviewPort();
      final device = DeviceReviewController(port);
      addTearDown(device.dispose);
      addTearDown(port.close);
      final overall = await pumpSetup(
        tester,
        step: OnboardingStep.local,
        mode: OnboardingMode.local,
        observation: facts(confirmed: true, localReady: false),
        deviceReview: device,
      );
      expect(find.textContaining('Ctrl+F9'), findsOneWidget);
      expect(port.confirmations, 0);
      for (final section in DeviceReviewSection.values) {
        final check = find.byKey(Key('device-check-${section.name}'));
        await tester.ensureVisible(check);
        await tester.tap(check);
        await tester.pump();
      }
      final confirm = find.byKey(const Key('device-confirm'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(port.confirmations, 1);
      expect(overall.value.facts.localSettingsReady, false);
      expect(overall.canContinue, false);
      expect(overall.value.step, OnboardingStep.local);
      expect(tester.takeException(), isNull);
    },
  );
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en', 'US'),
  ]) {
    testWidgets(
      'device review fits narrow scaled ${locale.toLanguageTag()} without changing defaults',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = FakeDeviceReviewPort();
        final device = DeviceReviewController(port);
        addTearDown(device.dispose);
        addTearDown(port.close);
        await pumpSetup(
          tester,
          step: OnboardingStep.local,
          mode: OnboardingMode.local,
          observation: facts(confirmed: true, localReady: false),
          deviceReview: device,
          locale: locale,
          scale: 1.6,
        );
        await tester.ensureVisible(find.byKey(const Key('device-confirm')));
        await tester.pumpAndSettle();
        expect(port.confirmations, 0);
        expect(device.value.checked, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'late bridge replies cannot revive a settings-invalidated observation',
    () async {
      final f = DeviceBridgeFixture();
      addTearDown(f.close);
      final events = f.adapter.invalidations.listen((_) {});
      addTearDown(events.cancel);
      final seen = Completer<BridgeEnvelope>();
      f.onRequest = (request) async {
        seen.complete(request);
      };
      final read = f.adapter.read();
      final rejected = expectLater(read, throwsStateError);
      final request = await seen.future;
      await f.pair.host.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'overlay.changed',
          sessionGeneration: 3,
          sequence: 1,
          payload: {},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await f.respond(request);
      await rejected;
      expect(
        () => f.adapter.confirm(
          '11111111111111111111111111111111',
          DeviceReviewSection.values.toSet(),
        ),
        throwsStateError,
      );
      f.onRequest = null;
      expect((await f.adapter.read()).canReview, true);
    },
  );
  test(
    'Host epoch and transport failure discard an earlier bridge ticket',
    () async {
      final f = DeviceBridgeFixture();
      addTearDown(f.close);
      final old = await f.adapter.read();
      f.session.advanceGeneration(4);
      expect(
        () => f.adapter.confirm(
          old.reviewKey!,
          DeviceReviewSection.values.toSet(),
        ),
        throwsStateError,
      );
      await f.adapter.read();
      await f.session.close();
      await expectLater(
        f.adapter.read(),
        throwsA(isA<BridgeDisconnectedException>()),
      );
      expect(
        () => f.adapter.confirm(
          old.reviewKey!,
          DeviceReviewSection.values.toSet(),
        ),
        throwsStateError,
      );
    },
  );
  testWidgets(
    'original-editor callback refreshes actual values and requires rechecking',
    (tester) async {
      final port = FakeDeviceReviewPort();
      final device = DeviceReviewController(port);
      addTearDown(device.dispose);
      addTearDown(port.close);
      var edits = 0;
      await pumpSetup(
        tester,
        step: OnboardingStep.local,
        mode: OnboardingMode.local,
        observation: facts(confirmed: true, localReady: false),
        deviceReview: device,
        editDeviceSettings: (section) async {
          expect(section, DeviceReviewSection.application);
          edits++;
          final raw = deviceWire(key: '33333333333333333333333333333333');
          (raw['application']! as Map<String, Object?>)['launchAtStartup'] =
              true;
          port.snapshot = DeviceReviewWire.parse(raw);
        },
      );
      for (final section in DeviceReviewSection.values) {
        device.check(section, true);
      }
      await tester.pump();
      final edit = find.byKey(const Key('device-edit-application'));
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(edits, 1);
      expect(port.confirmations, 0);
      expect(device.value.checked, isEmpty);
      expect(find.text('随 Windows 启动 · 开启'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'confirmation keeps navigation closed until the same pending operation exits',
    (tester) async {
      final port = FakeDeviceReviewPort();
      final device = DeviceReviewController(port);
      addTearDown(device.dispose);
      addTearDown(port.close);
      final pending = Completer<DeviceReviewSnapshot>();
      port.onConfirm = () => pending.future;
      await pumpSetup(
        tester,
        step: OnboardingStep.local,
        mode: OnboardingMode.local,
        observation: facts(confirmed: true, localReady: false),
        deviceReview: device,
      );
      for (final section in DeviceReviewSection.values) {
        device.check(section, true);
      }
      await tester.pump();
      final confirm = find.byKey(const Key('device-confirm'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('onboarding-back')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const Key('onboarding-close')))
            .onPressed,
        isNull,
      );
      pending.complete(
        DeviceReviewWire.parse(
          deviceWire(
            state: 'reviewed',
            key: '22222222222222222222222222222222',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(port.confirmations, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('preview device-review-dark', (tester) async {
    tester.view.physicalSize = const Size(1280, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final port = FakeDeviceReviewPort();
    final device = DeviceReviewController(port);
    addTearDown(device.dispose);
    addTearDown(port.close);
    await pumpSetup(
      tester,
      step: OnboardingStep.local,
      mode: OnboardingMode.local,
      observation: facts(confirmed: true, localReady: false),
      deviceReview: device,
      editDeviceSettings: (_) async {},
    );
    if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
      await expectLater(
        find.byKey(const Key('onboarding-capture')),
        matchesGoldenFile('goldens/device-review-dark.png'),
      );
    }
  });
}

class DeviceBridgeFixture {
  DeviceBridgeFixture({bool capabilities = true}) {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 3,
    );
    if (capabilities) {
      session.acceptHostCapabilities([BridgeDeviceReviewAdapter.capability]);
    }
    adapter = BridgeDeviceReviewAdapter(session);
    subscription = pair.host.incoming.listen((request) async {
      requests.add(request);
      if (onRequest != null) {
        await onRequest!(request);
      } else {
        await respond(request);
      }
    });
  }
  Future<void> respond(BridgeEnvelope request) => pair.host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      status: 'ok',
      payload:
          payload ??
          deviceWire(
            state: request.name.endsWith('confirm')
                ? 'reviewed'
                : 'reviewRequired',
            key: request.name.endsWith('confirm')
                ? '22222222222222222222222222222222'
                : '11111111111111111111111111111111',
          ),
    ),
  );
  final pair = InMemoryBridgeConnection.createPair();
  late final BridgeClientSession session;
  late final BridgeDeviceReviewAdapter adapter;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  Map<String, Object?>? payload;
  Future<void> Function(BridgeEnvelope)? onRequest;
  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}
