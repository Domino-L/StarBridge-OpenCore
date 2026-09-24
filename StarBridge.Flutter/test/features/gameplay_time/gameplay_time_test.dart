import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/gameplay_time/gameplay_time_controller.dart';
import 'package:starbridge_flutter/features/gameplay_time/gameplay_time_panel.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/settings/general_settings_page.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

class Harness {
  Harness({
    bool supported = true,
    bool historySupported = true,
    bool resetSupported = false,
    this.consent = 'allowed',
    this.showOnProfile = true,
    this.historyState = 'unchecked',
    this.oldProjection = false,
  }) {
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
    );
    if (supported) {
      session.acceptHostCapabilities([
        'gameplayTime.local',
        if (historySupported) 'gameplayTime.history',
        if (resetSupported) 'gameplayTime.reset',
      ]);
    }
    subscription = pair.host.incoming.listen((r) {
      if (r.name == 'bridge.cancel') return;
      requests.add(r);
      if (hold && r.name != 'account.getCurrent' ||
          holdNames.contains(r.name)) {
        held = r;
        return;
      }
      respond(r);
    });
    controller = GameplayTimeController(session, account);
  }
  final pair = InMemoryBridgeConnection.createPair();
  final account = ValueNotifier(
    const AccountProjection.loading().copyWith(
      sessionState: AccountSessionState.signedIn,
      generation: 1,
      operation: AccountOperation.none,
    ),
  );
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  late final GameplayTimeController controller;
  final requests = <BridgeEnvelope>[];
  String subject = 'synthetic-a';
  String consent;
  bool showOnProfile;
  String historyState;
  final bool oldProjection;
  String statusResult = 'available';
  String previewResult = 'preview';
  String confirmResult = 'imported';
  int historicalSeconds = 0;
  final holdNames = <String>{};
  final wrongContext = <String, String>{};
  String? error;
  int seconds = 0;
  bool hold = false;
  bool wrongOwner = false;
  BridgeEnvelope? held;

  void respond(BridgeEnvelope r) {
    if (r.name == 'gameplayTime.setConsent') {
      consent = r.payload['allowed'] == true ? 'allowed' : 'declined';
    }
    if (r.name == 'gameplayTime.setVisibility') {
      showOnProfile = r.payload['showOnProfile'] as bool;
    }
    if (r.name == 'gameplayTime.historyConfirm' &&
        confirmResult == 'imported') {
      historyState = 'imported';
      statusResult = 'imported';
      historicalSeconds = 5400;
    }
    final context = BridgeAccountContext(
      environment: wrongContext['environment'] ?? 'test',
      authority:
          wrongContext['authority'] ??
          (account.value.isLegacyAccount ? 'local' : 'scm'),
      subject: wrongOwner ? 'other' : subject,
    );
    unawaited(
      pair.host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: r.name,
          correlationId: r.correlationId,
          sessionGeneration: r.sessionGeneration,
          accountContext: context,
          status: 'ok',
          payload: r.name == 'gameplayTime.resetPreview'
              ? {
                  'schemaVersion': 1,
                  'state': 'ready',
                  'previewId': '0123456789abcdef0123456789abcdef',
                }
              : r.name == 'gameplayTime.resetConfirm'
              ? {'schemaVersion': 1, 'state': 'completed'}
              : r.name == 'gameplayTime.resetStatus'
              ? {'schemaVersion': 1, 'state': 'idle'}
              : r.name == 'gameplayTime.historyStatus'
              ? {'schemaVersion': 1, 'state': statusResult}
              : r.name == 'gameplayTime.historyConfirm'
              ? {'schemaVersion': 1, 'state': confirmResult}
              : r.name == 'gameplayTime.historyPreview'
              ? {
                  'schemaVersion': 1,
                  'state': previewResult,
                  if (previewResult == 'preview') ...{
                    'previewId': 'synthetic-preview',
                    'seconds': 5400,
                    'sessions': 3,
                    'incompleteSessions': 1,
                    'skippedFiles': 2,
                  },
                }
              : r.name == 'account.getCurrent'
              ? {'schemaVersion': 1, 'state': account.value.sessionState.name}
              : {
                  'schemaVersion': 1,
                  'consent': consent,
                  'seconds': seconds,
                  'savedSeconds': seconds,
                  'gameState': 'running',
                  'recording': error == null && consent == 'allowed',
                  'error': error,
                  if (!oldProjection) ...{
                    'showOnProfile': showOnProfile,
                    'historyState': historyState,
                    'historicalSeconds': historicalSeconds,
                  },
                },
        ),
      ),
    );
  }

  void changeAccount({bool signedIn = true}) {
    final generation = account.value.generation + 1;
    subject = 'synthetic-b';
    consent = 'unknown';
    historyState = 'unchecked';
    showOnProfile = true;
    historicalSeconds = 0;
    seconds = 0;
    session.advanceGeneration(generation);
    account.value = account.value.copyWith(
      generation: generation,
      sessionState: signedIn
          ? AccountSessionState.signedIn
          : AccountSessionState.signedOut,
    );
  }

  Future<void> close(WidgetTester tester) async {
    controller.dispose();
    account.dispose();
    await tester.runAsync(() async {
      await subscription.cancel();
      await session.close();
      await pair.host.close();
    });
  }
}

Widget app(Widget child, {Locale locale = const Locale('zh', 'CN')}) =>
    MaterialApp(
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        locale,
      ),
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('reset dialog states account-wide consequence and cancellation', (
    tester,
  ) async {
    final h = Harness(resetSupported: true);
    await tester.pumpWidget(app(GameplayTimePanel(controller: h.controller)));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('gameplay-reset-open')));
    await tester.tap(find.byKey(const Key('gameplay-reset-open')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('gameplay-reset-confirmation')),
      findsOneWidget,
    );
    expect(find.textContaining('其他设备联网后也会同步清零'), findsOneWidget);
    await tester.tap(find.text('保留时长'));
    await tester.pumpAndSettle();
    expect(find.byType(GameplayTimePanel), findsOneWidget,
        reason: 'Cancelling reset must not pop the underlying settings route');
    expect(find.byKey(const Key('gameplay-reset-open')), findsOneWidget);
    expect(
      h.requests.where((r) => r.name == 'gameplayTime.resetConfirm'),
      isEmpty,
    );
    await h.close(tester);
  });
  for (final dismissal in ['barrier', 'confirm', 'accountChange']) {
    testWidgets('reset $dismissal only closes its own dialog', (tester) async {
      final h = Harness(resetSupported: true);
      await tester.pumpWidget(app(GameplayTimePanel(controller: h.controller)));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('gameplay-reset-open')));
      await tester.tap(find.byKey(const Key('gameplay-reset-open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gameplay-reset-confirmation')), findsOneWidget);
      if (dismissal == 'confirm') {
        await tester.tap(find.byKey(const Key('gameplay-reset-confirm')));
      } else if (dismissal == 'accountChange') {
        h.changeAccount();
      } else {
        await tester.tapAt(const Offset(4, 4));
      }
      await tester.pumpAndSettle();
      expect(find.byType(GameplayTimePanel), findsOneWidget);
      expect(find.byKey(const Key('gameplay-reset-confirmation')), findsNothing);
      expect(h.requests.where((r) => r.name == 'gameplayTime.resetConfirm'),
          hasLength(dismissal == 'confirm' ? 1 : 0));
      await h.close(tester);
    });
  }
  testWidgets('reset cancellation sends no destructive request', (
    tester,
  ) async {
    final h = Harness(resetSupported: true);
    await tester.pump();
    final operation = h.controller.resetTime(() async => false);
    await tester.pump();
    await operation;
    expect(
      h.requests.where((r) => r.name == 'gameplayTime.resetPreview'),
      hasLength(1),
    );
    expect(
      h.requests.where((r) => r.name == 'gameplayTime.resetConfirm'),
      isEmpty,
    );
    await h.close(tester);
  });
  testWidgets('reset confirmation sends once and account change cancels', (
    tester,
  ) async {
    final h = Harness(resetSupported: true);
    await tester.pump();
    final first = h.controller.resetTime(() async => true);
    await tester.pump();
    await first;
    expect(
      h.requests.where((r) => r.name == 'gameplayTime.resetConfirm'),
      hasLength(1),
    );
    final confirm = Completer<bool>();
    final second = h.controller.resetTime(() => confirm.future);
    await tester.pump();
    h.changeAccount();
    confirm.complete(true);
    await tester.pump();
    await second;
    expect(
      h.requests.where((r) => r.name == 'gameplayTime.resetConfirm'),
      hasLength(1),
    );
    await h.close(tester);
  });
  for (final state in [
    AccountSessionState.legacySignedIn,
    AccountSessionState.legacyUnavailable,
  ]) {
    testWidgets('compatibility account exposes game time: $state', (
      tester,
    ) async {
      final h = Harness(consent: 'unknown');
      h.account.value = h.account.value.copyWith(sessionState: state);
      await tester.pumpWidget(app(GameplayTimePanel(controller: h.controller)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('gameplay-time-record-switch')),
        findsOneWidget,
      );
      expect(h.controller.value.seconds, 0);
      expect(
        h.requests.where((r) => r.name == 'gameplayTime.setConsent'),
        isEmpty,
      );
      await h.controller.setAllowed(true);
      await tester.pump();
      expect(h.controller.value.consent, 'allowed');
      expect(
        h.requests
            .lastWhere((r) => r.name == 'gameplayTime.setConsent')
            .accountContext
            ?.authority,
        'local',
      );
      h.changeAccount(signedIn: false);
      await tester.pump();
      expect(h.controller.value.seconds, isNull);
      await h.close(tester);
    });
  }
  testWidgets('recording explanation is read-only', (tester) async {
    final h = Harness();
    await tester.pumpWidget(app(GameplayTimePanel(controller: h.controller)));
    await tester.pumpAndSettle();
    final before = h.requests.length;
    await tester.tap(find.byKey(const Key('gameplay-time-explanation')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('关闭记录会保留已有时长'), findsOneWidget);
    expect(h.requests.length, before);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await h.close(tester);
  });
  testWidgets(
    'Bridge invalidation hides old totals before account refresh completes',
    (tester) async {
      final h = Harness();
      await tester.pump();
      h.seconds = 7200;
      await tester.pump(const Duration(seconds: 5));
      expect(h.controller.value.seconds, 7200);
      await h.pair.host.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.changed',
          payload: {},
          sessionGeneration: 2,
          sequence: 1,
        ),
      );
      await tester.pump();
      expect(h.controller.value.visible, isFalse);
      expect(h.controller.value.seconds, isNull);
      h.subject = 'synthetic-b';
      h.seconds = 0;
      h.account.value = h.account.value.copyWith(generation: 2);
      await tester.pump();
      expect(h.controller.value.visible, isTrue);
      expect(h.controller.value.seconds, 0);
      await h.close(tester);
    },
  );
  testWidgets(
    'consent is explicit, actions single-flight, retry and time survive stop',
    (tester) async {
      final h = Harness(consent: 'unknown');
      await tester.pump();
      expect(h.controller.value.consent, 'unknown');
      expect(
        h.requests.where((r) => r.name == 'gameplayTime.setConsent'),
        isEmpty,
      );
      h.hold = true;
      final allow = h.controller.setAllowed(true);
      await tester.pump();
      expect(h.controller.value.busy, isTrue);
      await h.controller.setAllowed(true);
      expect(
        h.requests.where((r) => r.name == 'gameplayTime.setConsent').length,
        1,
      );
      h.hold = false;
      h.respond(h.held!);
      await tester.pump();
      await allow;
      expect(h.controller.value.consent, 'allowed');
      h.seconds = 3665;
      await tester.pump(const Duration(seconds: 5));
      expect(h.controller.value.seconds, 3665);
      h.error = 'gameplay.write_failed';
      final stop = h.controller.setAllowed(false);
      await tester.pump();
      await stop;
      expect(h.controller.value.error, 'gameplay.write_failed');
      h.error = null;
      final retry = h.controller.retry();
      await tester.pump();
      await retry;
      expect(h.controller.value.consent, 'declined');
      expect(h.controller.value.seconds, 3665);
      expect(h.requests.last.name, 'gameplayTime.retry');
      await h.close(tester);
    },
  );

  testWidgets(
    'timeout never silently retries consent; later confirmation resolves it',
    (tester) async {
      final h = Harness();
      await tester.pump();
      final allow = h.controller.setAllowed(true);
      await tester.pump();
      await allow;
      h.hold = true;
      final stop = h.controller.setAllowed(false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      await stop;
      expect(h.controller.value.error, 'stopUnconfirmed');
      h.hold = false;
      final writes = h.requests
          .where((r) => r.name.endsWith('setConsent'))
          .length;
      await tester.pump(const Duration(seconds: 5));
      expect(h.controller.value.error, 'stopUnconfirmed');
      expect(
        h.requests.where((r) => r.name.endsWith('setConsent')).length,
        writes,
      );
      final retry = h.controller.retry();
      await tester.pump();
      await retry;
      expect(h.controller.value.consent, 'declined');
      expect(h.controller.value.error, isNull);
      await h.close(tester);
    },
  );

  testWidgets(
    'account change clears immediately and rejects old response; logout stops polling',
    (tester) async {
      final h = Harness();
      await tester.pump();
      h.hold = true;
      final pending = h.controller.retry();
      await tester.pump();
      final old = h.held!;
      h.changeAccount();
      expect(h.controller.value.seconds, isNull);
      h.hold = false;
      h.respond(old);
      await tester.pump();
      await pending;
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        h.controller.value.seconds,
        0,
        reason:
            'error=${h.controller.value.error} requests=${h.requests.map((r) => "${r.name}:${r.sessionGeneration}").join(",")}',
      );
      expect(h.controller.value.consent, 'unknown');
      h.changeAccount(signedIn: false);
      expect(h.controller.value.visible, isFalse);
      final count = h.requests.length;
      await tester.pump(const Duration(seconds: 30));
      expect(h.requests.length, count);
      await h.close(tester);
    },
  );

  testWidgets(
    'unsupported Host sends no requests; wrong owner never displays totals',
    (tester) async {
      final old = Harness(supported: false);
      await tester.pump(const Duration(seconds: 30));
      expect(old.requests, isEmpty);
      expect(old.controller.value.error, 'unsupported');
      await old.close(tester);
      final h = Harness();
      await tester.pump();
      h.wrongOwner = true;
      h.seconds = 9999;
      await tester.pump(const Duration(seconds: 5));
      expect(h.controller.value.seconds, 0);
      expect(h.controller.value.error, 'unavailable');
      await h.close(tester);
    },
  );

  for (final locale in AppStrings.supportedLocales) {
    for (final width in [360.0, 1100.0]) {
      testWidgets(
        'recording panel respects $locale at width $width and enlarged text',
        (tester) async {
          final h = Harness();
          await tester.pump();
          await tester.binding.setSurfaceSize(Size(width, 900));
          await tester.pumpWidget(
            app(
              MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
                child: SizedBox(
                  height: 850,
                  child: GeneralSettingsPage(
                    preferences: InMemoryAppPreferences(),
                    gameplayTime: h.controller,
                  ),
                ),
              ),
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();
          final recording = find.byKey(
            const Key('gameplay-time-record-switch'),
          );
          final visibility = find.byKey(
            const Key('gameplay-time-profile-switch'),
          );
          expect(tester.widget<Switch>(recording).value, isTrue);
          expect(tester.widget<Switch>(visibility).value, isTrue);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(recording);
          await tester.pumpAndSettle();
          await tester.tap(recording);
          await tester.pumpAndSettle();
          expect(tester.widget<Switch>(recording).value, isFalse);
          h.error = 'gameplay.write_failed';
          await tester.tap(recording);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('gameplay-time-retry')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await h.close(tester);
          await tester.binding.setSurfaceSize(null);
        },
      );
    }
  }
  testWidgets(
    'profile only shows readonly metrics in owner and visitor preview',
    (tester) async {
      final h = Harness()..seconds = 3600;
      final profile = createPersonalProfileModule(
        InMemoryPersonalProfileAdapter.forReview(signedIn: true),
      );
      await profile.initialize();
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      await tester.pumpWidget(
        app(
          SizedBox(
            height: 1000,
            child: PersonalProfilePage(
              module: profile,
              gameplayTime: h.controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gameplay-time-panel')), findsNothing);
      expect(find.textContaining('本机累计'), findsOneWidget);
      await tester.tap(find.text('预览访客视角'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gameplay-time-panel')), findsNothing);
      expect(find.textContaining('本机累计'), findsNothing);
      expect(find.text('已有历史时长'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      profile.dispose();
      await h.close(tester);
      await tester.binding.setSurfaceSize(null);
    },
  );
}
