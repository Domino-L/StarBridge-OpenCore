
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_onboarding_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_recognition_check_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_controller.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_page.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_progress.dart';
import 'package:starbridge_flutter/features/onboarding/recognition_check_controller.dart';
import 'package:starbridge_flutter/features/onboarding/recognition_check_port.dart';

import 'onboarding_test_support.dart';

Map<String, Object?> _wire({
  String state = 'ready',
  String? handle = 'Pilot-Example',
  bool aboard = false,
}) => {
  'schemaVersion': 1,
  'state': state,
  'version': 'LIVE',
  'handle': ?handle,
  'server': {
    'state': state == 'ready' ? 'connected' : 'unknown',
    if (state == 'ready') 'region': 'EU',
  },
  'location': {
    'state': state == 'ready' ? 'confirmed' : 'unknown',
    if (state == 'ready') 'englishName': 'Area18',
    if (state == 'ready') 'zhHans': '18区',
  },
  'ship': {
    'state': aboard ? 'confirmed' : 'unknown',
    if (aboard) 'key': 'synthetic',
    if (aboard) 'englishName': 'Cutlass Black',
  },
};

final class FakeRecognitionPort implements RecognitionCheckPort {
  FakeRecognitionPort([this.snapshot]);
  RecognitionCheckSnapshot? snapshot;
  bool supportedValue = true;
  int reads = 0;
  @override
  bool get supported => supportedValue;
  @override
  Future<RecognitionCheckSnapshot> read() async {
    reads++;
    final value = snapshot;
    if (value == null) throw StateError('synthetic');
    return value;
  }
}

Future<(OnboardingController, RecognitionCheckController)> _pump(
  WidgetTester tester,
  FakeRecognitionPort port, {
  OnboardingStep step = OnboardingStep.verify,
  Size size = const Size(1280, 720),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fake = FakeOnboardingPort(facts(confirmed: true));
  fake.restored = OnboardingCheckpoint(
    step: step,
    mode: OnboardingMode.local,
    sourceKey: fake.facts.sourceKey,
    evidenceKey: fake.facts.evidenceKey,
  );
  final controller = OnboardingController(fake);
  addTearDown(controller.dispose);
  final check = RecognitionCheckController(port);
  addTearDown(check.dispose);
  const locale = Locale('zh', 'CN');
  await tester.pumpWidget(
    MaterialApp(
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        locale,
      ),
      locale: locale,
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: RepaintBoundary(
        key: const Key('capture'),
        child: OnboardingPage(
          controller: controller,
          onClose: () {},
          recognition: check,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return (controller, check);
}

String _next(WidgetTester tester) =>
    (tester
                .widget<FilledButton>(find.byKey(const Key('onboarding-next')))
                .child!
            as Text)
        .data!;

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

  group('wire', () {
    test('ready payload decodes; omitted nulls are fine', () {
      final s = parseRecognitionCheck(_wire(aboard: true));
      expect(s.ready, isTrue);
      expect(s.handle, 'Pilot-Example');
      expect(s.location('zh', 'CN'), '18区');
      expect(s.ship('en', null), 'Cutlass Black');
      final closed = parseRecognitionCheck(
        _wire(state: 'notRunning', handle: null),
      );
      expect(closed.ready, isFalse);
      expect(closed.gameClosed, isTrue);
    });

    test('unknown sub-states are refused', () {
      final bad = _wire()..['server'] = {'state': 'maybe'};
      expect(() => parseRecognitionCheck(bad), throwsFormatException);
      expect(
        () => parseRecognitionCheck({..._wire(), 'schemaVersion': 2}),
        throwsFormatException,
      );
    });

    test('a ready state without a Handle is not a pass', () {
      expect(parseRecognitionCheck(_wire(handle: null)).ready, isFalse);
    });

    test('the optional check is saved as the summary page', () {
      final wire = BridgeOnboardingAdapter.checkpointWire(
        const OnboardingCheckpoint(
          step: OnboardingStep.verify,
          mode: OnboardingMode.local,
        ),
      );
      expect(wire['step'], 'summary');
    });
  });

  group('controller', () {
    test('only a ready read passes, and a pass stays latched', () async {
      final port = FakeRecognitionPort(
        parseRecognitionCheck(_wire(state: 'notRunning', handle: null)),
      );
      final check = RecognitionCheckController(
        port,
        interval: const Duration(hours: 1),
      );
      addTearDown(check.dispose);
      expect(port.reads, 0, reason: 'nothing is read before the step opens');
      check.start();
      await Future<void>.delayed(Duration.zero);
      expect(check.value.outcome, RecognitionCheckOutcome.skipped);
      port.snapshot = parseRecognitionCheck(_wire());
      check.stop();
      check.start();
      await Future<void>.delayed(Duration.zero);
      expect(check.value.outcome, RecognitionCheckOutcome.passed);
      port.snapshot = parseRecognitionCheck(
        _wire(state: 'notRunning', handle: null),
      );
      check.stop();
      check.start();
      await Future<void>.delayed(Duration.zero);
      expect(check.value.passed, isTrue);
      check.stop();
      expect(check.polling, isFalse);
    });

    test('unsupported Host means no reads and an honest unavailable', () {
      final port = FakeRecognitionPort()..supportedValue = false;
      final check = RecognitionCheckController(port);
      addTearDown(check.dispose);
      check.start();
      expect(port.reads, 0);
      expect(check.value.outcome, RecognitionCheckOutcome.unavailable);
    });
  });

  test('breakpoints follow the approved preview', () {
    expect(onboardingProgressKind(1440), OnboardingProgressKind.horizontal);
    expect(onboardingProgressKind(1280), OnboardingProgressKind.horizontal);
    expect(onboardingProgressKind(1100), OnboardingProgressKind.rail);
    expect(onboardingProgressKind(900), OnboardingProgressKind.rail);
    expect(onboardingProgressKind(760), OnboardingProgressKind.bar);
  });

  testWidgets('waiting for the game offers a skip, not a pass', (tester) async {
    final port = FakeRecognitionPort(
      parseRecognitionCheck(_wire(state: 'notRunning', handle: null)),
    );
    final (controller, check) = await _pump(tester, port);
    expect(controller.value.step, OnboardingStep.verify);
    expect(
      find.byKey(const Key('recognition-banner-notRunning')),
      findsOneWidget,
    );
    expect(_next(tester), '跳过此步');
    await tester.tap(find.byKey(const Key('onboarding-next')));
    await tester.pump();
    await tester.pump();
    expect(controller.value.step, OnboardingStep.summary);
    expect(check.polling, isFalse, reason: 'polling stops off the step');
    expect(
      find.byKey(const Key('summary-recognition-skipped')),
      findsOneWidget,
    );
  });

  for (final (name, size, kind) in [
    ('verify-ready-wide', const Size(1280, 720), 'horizontal'),
    ('verify-ready-medium', const Size(1100, 760), 'rail'),
    ('verify-ready-narrow', const Size(760, 900), 'bar'),
  ]) {
    testWidgets('ready recognition passes ($name)', (tester) async {
      final port = FakeRecognitionPort(parseRecognitionCheck(_wire()));
      final (controller, check) = await _pump(tester, port, size: size);
      expect(find.byKey(Key('onboarding-progress-$kind')), findsOneWidget);
      expect(find.byKey(const Key('recognition-banner-ready')), findsOneWidget);
      expect(find.text('18区'), findsOneWidget);
      expect(_next(tester), '继续');
      if (!const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE')) {
        await expectLater(
          find.byKey(const Key('capture')),
          matchesGoldenFile('goldens/$name.png'),
        );
      }
      if (name == 'verify-ready-wide') {
        await tester.tap(find.byKey(const Key('onboarding-next')));
        await tester.pump();
        await tester.pump();
        expect(controller.value.step, OnboardingStep.summary);
        expect(
          find.byKey(const Key('summary-recognition-saved')),
          findsOneWidget,
        );
        expect(find.text('已通过'), findsWidgets);
      }
      check.stop();
    });
  }
}
