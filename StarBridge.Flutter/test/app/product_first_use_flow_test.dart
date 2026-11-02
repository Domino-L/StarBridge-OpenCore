import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/runtime/product_first_use_flow.dart';
import 'package:starbridge_flutter/app/runtime/startup_prompt_queue.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_onboarding_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_page.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_flutter/platform/host/native_host_connector.dart';

import '../features/onboarding/bridge_onboarding_adapter_test.dart' show wire;

final class _Host implements NativeHostLease {
  _Host({bool enabled = true, bool startup = false}) {
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 3)
      ..acceptHostCapabilities([
        if (enabled) BridgeOnboardingAdapter.capability,
        if (startup) 'onboarding.startup.v1',
      ]);
    subscription = pair.host.incoming.listen((request) async {
      requests.add(request);
      final isGuide = request.name.startsWith('onboarding.');
      final payload = request.name == 'onboarding.startup.read'
          ? <String, Object?>{
              'schemaVersion': 1,
              'eligibility': startupEligibility ?? eligibility,
              'reason': (startupEligibility ?? eligibility) == 'unknown'
                  ? 'unreadableProgress'
                  : (startupEligibility ?? eligibility) == 'returning'
                  ? 'previousUse'
                  : 'freshInstallation',
              'hasProgress': false,
            }
          : wire();
      if (payload['facts'] case final Map<String, Object?> facts) {
        facts['eligibility'] = eligibility;
      }
      if (request.name == 'onboarding.saveProgress') {
        payload['saved'] = request.payload['checkpoint'];
      }
      await pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          status: isGuide ? 'ok' : 'error',
          payload: isGuide ? payload : const {},
          error: isGuide
              ? null
              : const BridgeErrorBody(
                  code: 'fixture.unavailable',
                  message: 'Unavailable in bounded fixture',
                  retryable: false,
                ),
        ),
      );
    });
  }
  final pair = InMemoryBridgeConnection.createPair();
  final requests = <BridgeEnvelope>[];
  late final StreamSubscription<BridgeEnvelope> subscription;
  String eligibility = 'firstUse';
  String? startupEligibility;
  final termination = Completer<NativeHostTermination>();
  @override
  late final BridgeClientSession session;
  @override
  Future<NativeHostTermination> get terminated => termination.future;
  bool closed = false;
  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await subscription.cancel();
    await session.close();
    await pair.host.close();
  }
}

Future<void> _pump(WidgetTester tester, StartupPromptQueue queue) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [queue],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        const Locale('en', 'US'),
      ),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: const Scaffold(body: Text('Original primary route')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a queued recovery reread becoming healthy resumes the original automatic offer',
    (tester) async {
      final host = _Host(startup: true)..startupEligibility = 'unknown';
      final preferences = InMemoryAppPreferences();
      final composition = AppComposition.forConnectedProduct(
        nativeHost: host,
        preferences: preferences,
      );
      final queue = StartupPromptQueue(
        quietPeriod: const Duration(milliseconds: 5),
      );
      var ready = false;
      final flow = ProductFirstUseFlow(
        composition: composition,
        queue: queue,
        ready: () => ready,
        current: () => true,
      );
      await _pump(tester, queue);
      flow.wake();
      await tester.pumpAndSettle();
      expect(flow.blocksOptionalPrompts, true);
      host.startupEligibility = 'firstUse';
      ready = true;
      queue.wake();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('first-use-recovery-dialog')), findsNothing);
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.textContaining('1 of 6 · Mode'), findsOneWidget);
      expect(find.text('Get your StarBridge ready'), findsNothing);
      expect(find.byKey(const Key('onboarding-back')), findsNothing);
      expect(
        host.requests.where(
          (r) => ['onboarding.execute', 'onboarding.finish'].contains(r.name),
        ),
        isEmpty,
      );
      // Only the opening UI checkpoint is recorded so any exit can resume.
      final opening = host.requests
          .where((r) => r.name == 'onboarding.saveProgress')
          .toList();
      expect(opening, hasLength(1));
      expect((opening.single.payload['checkpoint']! as Map)['step'], 'mode');
      await tester.pumpWidget(const SizedBox());
      flow.dispose();
      queue.dispose();
      composition.dispose();
      preferences.dispose();
      await tester.runAsync(host.close);
      await tester.pump();
    },
  );
  for (final choice in ['keep', 'recheck', 'open']) {
    testWidgets(
      'product recovery $choice uses original reads and navigation only',
      (tester) async {
        final host = _Host(startup: true)..eligibility = 'unknown';
        final preferences = InMemoryAppPreferences();
        final composition = AppComposition.forConnectedProduct(
          nativeHost: host,
          preferences: preferences,
        );
        final queue = StartupPromptQueue(
          quietPeriod: const Duration(milliseconds: 5),
        );
        final flow = ProductFirstUseFlow(
          composition: composition,
          queue: queue,
          ready: () => true,
          current: () => true,
        );
        await _pump(tester, queue);
        flow.wake();
        await tester.pumpAndSettle();
        final reads = host.requests
            .where((r) => r.name == 'onboarding.startup.read')
            .length;
        if (choice == 'recheck') host.eligibility = 'returning';
        await tester.tap(find.byKey(Key('first-use-recovery-$choice')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('first-use-recovery-dialog')),
          findsNothing,
        );
        expect(
          find.byType(OnboardingPage),
          choice == 'open' ? findsOneWidget : findsNothing,
        );
        expect(
          host.requests
              .where((r) => r.name == 'onboarding.startup.read')
              .length,
          reads + (choice == 'recheck' ? 1 : 0),
        );
        expect(
          host.requests.where(
            (r) => [
              'onboarding.execute',
              'onboarding.finish',
              'onboarding.saveProgress',
            ].contains(r.name),
          ),
          isEmpty,
        );
        // No second offer and no implicit completed marker after keeping/rechecking.
        flow.wake();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('first-use-recovery-dialog')),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
        flow.dispose();
        queue.dispose();
        composition.dispose();
        preferences.dispose();
        await tester.runAsync(host.close);
        await tester.pump();
      },
    );
  }
  testWidgets(
    'unknown startup evidence cancels an older queued automatic setup even when guide facts remain firstUse',
    (tester) async {
      final host = _Host(startup: true);
      final preferences = InMemoryAppPreferences();
      final composition = AppComposition.forConnectedProduct(
        nativeHost: host,
        preferences: preferences,
      );
      final queue = StartupPromptQueue(
        quietPeriod: const Duration(milliseconds: 5),
      );
      var ready = false;
      final flow = ProductFirstUseFlow(
        composition: composition,
        queue: queue,
        ready: () => ready,
        current: () => true,
      );
      await _pump(tester, queue);
      flow.wake();
      await tester.pumpAndSettle();
      expect(flow.blocksOptionalPrompts, true);
      host.startupEligibility = 'unknown';
      flow.wake();
      await tester.pumpAndSettle();
      ready = true;
      queue.wake();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('first-use-recovery-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('first-use-recovery-keep')));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsNothing);
      expect(
        host.requests.where(
          (r) => [
            'onboarding.execute',
            'onboarding.finish',
            'onboarding.saveProgress',
          ].contains(r.name),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      flow.dispose();
      queue.dispose();
      composition.dispose();
      preferences.dispose();
      await tester.runAsync(host.close);
      await tester.pump();
    },
  );
  testWidgets(
    'unknown original records present recovery choices, not automatic setup or writes',
    (tester) async {
      final host = _Host(startup: true)..eligibility = 'unknown';
      final preferences = InMemoryAppPreferences();
      final composition = AppComposition.forConnectedProduct(
        nativeHost: host,
        preferences: preferences,
      );
      final queue = StartupPromptQueue(
        quietPeriod: const Duration(milliseconds: 5),
      );
      final flow = ProductFirstUseFlow(
        composition: composition,
        queue: queue,
        ready: () => true,
        current: () => true,
      );
      await _pump(tester, queue);
      flow.wake();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('first-use-recovery-dialog')),
        findsOneWidget,
      );
      expect(find.byType(OnboardingPage), findsNothing);
      expect(
        host.requests.where(
          (r) =>
              r.name == 'onboarding.execute' ||
              r.name == 'onboarding.finish' ||
              r.name == 'onboarding.saveProgress',
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      flow.dispose();
      queue.dispose();
      composition.dispose();
      preferences.dispose();
      await tester.pump();
      await host.close();
    },
  );
  testWidgets(
    'product manual entry consumes the queued startup offer and preserves original owners',
    (tester) async {
      final host = _Host();
      final preferences = InMemoryAppPreferences();
      final composition = AppComposition.forConnectedProduct(
        nativeHost: host,
        preferences: preferences,
      );
      final queue = StartupPromptQueue(
        quietPeriod: const Duration(milliseconds: 5),
      );
      var ready = false, closed = false;
      final flow = ProductFirstUseFlow(
        composition: composition,
        queue: queue,
        ready: () => ready,
        current: () => true,
      );
      Future<void> close() async {
        if (closed) return;
        closed = true;
        flow.dispose();
        queue.dispose();
        composition.dispose();
        preferences.dispose();
        await tester.pump(); // Let the production async resource exit progress.
        await host.close();
      }

      addTearDown(close);
      await _pump(tester, queue);
      flow.wake();
      await tester.pumpAndSettle();
      expect(flow.blocksOptionalPrompts, true);
      expect(find.byType(OnboardingPage), findsNothing);
      final originalAccount = composition.account;
      final originalOverlay = composition.overlaySettings;
      final route = flow.open(queue.navigator!.context);
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding-close')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
      await route;
      ready = true;
      flow.wake();
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsNothing);
      expect(identical(composition.account, originalAccount), true);
      expect(identical(composition.overlaySettings, originalOverlay), true);
      expect(
        host.requests.where(
          (r) =>
              r.name == 'onboarding.execute' || r.name == 'onboarding.finish',
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      await close();
      await tester.pump();
    },
  );
  for (final eligibility in ['firstUse', 'returning', 'unknown']) {
    testWidgets('product automatic route obeys Host $eligibility eligibility', (
      tester,
    ) async {
      final host = _Host()..eligibility = eligibility;
      final preferences = InMemoryAppPreferences();
      final composition = AppComposition.forConnectedProduct(
        nativeHost: host,
        preferences: preferences,
      );
      final queue = StartupPromptQueue(
        quietPeriod: const Duration(milliseconds: 5),
      );
      final ownsDeviceChoices = <bool>[];
      final flow = ProductFirstUseFlow(
        composition: composition,
        queue: queue,
        ready: () => true,
        current: () => true,
        onOwnsDeviceChoices: ownsDeviceChoices.add,
      );
      var closed = false;
      Future<void> close() async {
        if (closed) return;
        closed = true;
        flow.dispose();
        queue.dispose();
        composition.dispose();
        preferences.dispose();
        await tester.pump();
        await host.close();
      }

      addTearDown(close);
      expect(identical(composition.firstUseSession, host.session), true);
      await _pump(tester, queue);
      flow.wake();
      await tester.pumpAndSettle();
      expect(
        find.byType(OnboardingPage),
        eligibility == 'firstUse' ? findsOneWidget : findsNothing,
      );
      // Setup holds the standalone startup prompt until Host eligibility is
      // known, then keeps it only when setup will ask the choice itself.
      expect(ownsDeviceChoices.first, true);
      expect(ownsDeviceChoices.last, eligibility == 'firstUse');
      expect(
        host.requests.where(
          (r) =>
              r.name == 'onboarding.execute' || r.name == 'onboarding.finish',
        ),
        isEmpty,
      );
      if (eligibility == 'firstUse') {
        expect(flow.blocksOptionalPrompts, true);
        flow.wake();
        await flow.open(queue.navigator!.context);
        expect(find.byType(OnboardingPage), findsOneWidget);
        await tester.tap(find.byKey(const Key('onboarding-close')));
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        for (var index = 0; index < 10 && flow.blocksOptionalPrompts; index++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        // Opening checkpoint plus the explicit close-time save.
        expect(
          host.requests.where((r) => r.name == 'onboarding.saveProgress'),
          hasLength(2),
        );
        expect(
          host.requests.where((r) => r.name == 'onboarding.finish'),
          isEmpty,
        );
        expect(
          find.byType(OnboardingPage),
          findsNothing,
          reason: 'A saved exit must pop the real product route without claiming completion',
        );
        expect(flow.blocksOptionalPrompts, false);
        flow.wake();
        await tester.pumpAndSettle();
        expect(find.byType(OnboardingPage), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      await close();
      await tester.pump();
    });
  }
  testWidgets('default-off product has no first-use read or manual entry', (
    tester,
  ) async {
    final host = _Host(enabled: false);
    final preferences = InMemoryAppPreferences();
    final composition = AppComposition.forConnectedProduct(
      nativeHost: host,
      preferences: preferences,
    );
    final queue = StartupPromptQueue(
      quietPeriod: const Duration(milliseconds: 5),
    );
    final flow = ProductFirstUseFlow(
      composition: composition,
      queue: queue,
      ready: () => true,
      current: () => true,
    );
    var closed = false;
    Future<void> close() async {
      if (closed) return;
      closed = true;
      flow.dispose();
      queue.dispose();
      composition.dispose();
      preferences.dispose();
      await tester.pump();
      await host.close();
    }

    addTearDown(close);
    await _pump(tester, queue);
    flow.wake();
    await flow.open(queue.navigator!.context);
    await tester.pumpAndSettle();
    expect(flow.supported, false);
    expect(find.byType(OnboardingPage), findsNothing);
    expect(
      host.requests.where((r) => r.name.startsWith('onboarding.')),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
    await close();
    await tester.pump();
  });
}
