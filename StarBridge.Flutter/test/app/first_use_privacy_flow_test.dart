import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/runtime/first_use_privacy_flow.dart';
import 'package:starbridge_flutter/app/runtime/startup_prompt_queue.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_port.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';

void main() {
  testWidgets(
    'notice has no editor controls; adjust closes it without saving or applying',
    (tester) async {
      final h = await Harness.create(tester);
      await h.settle(tester);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('启用状态共享'), findsNWidgets(2));
      final summary = tester
          .widget<Text>(find.byKey(const Key('first-privacy-fleet-summary')))
          .data!;
      expect(summary, contains('逐个确认'));
      expect(summary, contains('主舰队功能暂未开放'));
      await tester.tap(find.byKey(const Key('first-privacy-adjust')));
      await h.settle(tester);
      expect(h.adjustments, 1);
      expect(h.port.writes, 0);
      expect(h.port.applies, 0);
      expect(
        find.byKey(const Key('first-privacy-choice-dialog')),
        findsNothing,
      );
      h.flow.wake();
      await h.settle(tester);
      expect(
        find.byKey(const Key('first-privacy-choice-dialog')),
        findsNothing,
      );
      h.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'existing saved choices are preserved without a first-use prompt',
    (tester) async {
      final h = await Harness.create(tester, ready: false);
      h.port.snapshot = LocalPrivacySnapshot(
        revision: 1,
        settings: LocalPrivacySettings.editorDefaults.copyWith(
          fleetFields: 1,
          fleetAllMembersCanView: false,
          fleetAdministratorsCanView: true,
          roomAllMembersCanView: false,
        ),
      );
      h.ready = true;
      h.flow.wake();
      await h.settle(tester);
      expect(
        find.byKey(const Key('first-privacy-choice-dialog')),
        findsNothing,
      );
      expect(h.port.writes, 0);
      expect(h.port.applies, 0);
      expect(h.port.snapshot.settings!.fleetFields, 1);
      h.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'logout during a delayed save cannot apply to a different account',
    (tester) async {
      final h = await Harness.create(tester);
      await h.settle(tester);
      final saved = Completer<LocalPrivacySnapshot>();
      h.port.pendingSave = saved;
      await tester.tap(find.byKey(const Key('first-privacy-accept')));
      await tester.pump();
      h.port.events.add(null);
      await h.account.logout();
      await tester.pumpAndSettle();
      saved.complete(
        LocalPrivacySnapshot(
          revision: 1,
          settings: LocalPrivacySettings.editorDefaults,
        ),
      );
      await h.settle(tester);
      expect(h.port.applies, 0);
      expect(
        find.byKey(const Key('first-privacy-choice-dialog')),
        findsNothing,
      );
      h.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'first read failure recovers silently; existing choices are preserved',
    (tester) async {
      final h = await Harness.create(tester, ready: false);
      h.port.snapshot = LocalPrivacySnapshot(
        revision: 1,
        settings: LocalPrivacySettings.editorDefaults.copyWith(
          fleetFields: 33,
          roomFields: 18,
          fleetAllMembersCanView: false,
          fleetAdministratorsCanView: true,
        ),
      );
      h.port.failRead = true;
      h.ready = true;
      h.flow.wake();
      await h.settle(tester);
      expect(
        find.byKey(const Key('first-privacy-choice-dialog')),
        findsNothing,
      );
      h.port.failRead = false;
      await tester.pump(const Duration(seconds: 10));
      await h.settle(tester);
      expect(
        find.byKey(const Key('first-privacy-choice-dialog')),
        findsNothing,
      );
      expect(h.port.snapshot.settings!.fleetFields, 33);
      expect(h.port.snapshot.settings!.roomFields, 18);
      expect(h.port.snapshot.settings!.fleetAllMembersCanView, false);
      expect(h.port.applies, 0);
      h.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('small window keeps actions visible without overflow', (
    tester,
  ) async {
    final h = await Harness.create(tester);
    tester.view.physicalSize = const Size(420, 600);
    await h.settle(tester);
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const Key('first-privacy-decline')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('first-privacy-accept')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('first-privacy-decline')));
    await tester.pumpAndSettle();
    h.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  for (final accept in [true, false]) {
    testWidgets(
      '${accept ? 'accept' : 'decline'} is explicit and remembered across a new flow',
      (tester) async {
        final h = await Harness.create(tester);
        await h.settle(tester);
        expect(h.port.writes, 0);
        expect(h.port.applies, 0);
        expect(
          find.byKey(const Key('first-privacy-choice-dialog')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(
            Key(accept ? 'first-privacy-accept' : 'first-privacy-decline'),
          ),
        );
        await tester.pumpAndSettle();
        expect(h.port.writes, 1);
        expect(h.port.applies, accept ? 1 : 0);
        expect(h.port.snapshot.settings!.publicationEnabled, accept);
        expect(h.port.snapshot.settings!.fleetFields, 0);
        expect(h.port.snapshot.settings!.roomFields, 15);
        expect(
          find.byKey(const Key('first-privacy-choice-dialog')),
          findsNothing,
        );
        h.restartFlow();
        await h.settle(tester);
        expect(
          find.byKey(const Key('first-privacy-choice-dialog')),
          findsNothing,
        );
        expect(h.port.writes, 1);
        h.dispose();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'login route finishes before privacy, then optional startup prompt',
    (tester) async {
      final h = await Harness.create(tester, ready: false);
      final manual = showDialog<void>(
        context: h.key.currentContext!,
        builder: (_) => const AlertDialog(title: Text('login')),
      );
      h.ready = true;
      h.flow.wake();
      var optional = 0;
      h.queue.enqueue(
        'startup',
        priority: 200,
        eligible: () => !h.flow.blocksOptionalPrompt,
        show: () async {
          optional++;
        },
      );
      await h.settle(tester);
      expect(find.text('login'), findsOneWidget);
      expect(
        find.byKey(const Key('first-privacy-choice-dialog')),
        findsNothing,
      );
      expect(optional, 0);
      h.key.currentState!.pop();
      await manual;
      await h.settle(tester);
      expect(
        find.byKey(const Key('first-privacy-choice-dialog')),
        findsOneWidget,
      );
      expect(optional, 0);
      await tester.tap(find.byKey(const Key('first-privacy-decline')));
      await tester.pumpAndSettle();
      expect(optional, 0);
      await h.settle(tester);
      expect(optional, 1);
      h.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed save stays open; retries do not race publication status',
    (tester) async {
      final h = await Harness.create(tester);
      h.port.failSave = true;
      await h.settle(tester);
      await tester.tap(find.byKey(const Key('first-privacy-accept')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('first-privacy-choice-dialog')),
        findsOneWidget,
      );
      expect(h.port.applies, 0);
      h.port.failSave = false;
      await tester.tap(find.byKey(const Key('first-privacy-accept')));
      await tester.pumpAndSettle();
      expect(h.port.applies, 1);
      expect(
        find.byKey(const Key('first-privacy-choice-dialog')),
        findsNothing,
      );
      h.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'account invalidation dismisses only its own prompt and cannot apply stale choice',
    (tester) async {
      final h = await Harness.create(tester);
      await h.settle(tester);
      final manual = showDialog<void>(
        context: h.key.currentContext!,
        builder: (_) => const AlertDialog(title: Text('manual')),
      );
      h.port.events.add(null);
      await h.account.logout();
      await tester.pumpAndSettle();
      expect(find.text('manual'), findsOneWidget);
      expect(
        find.byKey(const Key('first-privacy-choice-dialog')),
        findsNothing,
      );
      expect(h.port.writes, 0);
      expect(h.port.applies, 0);
      h.key.currentState!.pop();
      await manual;
      h.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('unknown Host metadata never opens consent or writes defaults', (
    tester,
  ) async {
    final h = await Harness.create(tester, metadata: null);
    await h.settle(tester);
    expect(find.byKey(const Key('first-privacy-choice-dialog')), findsNothing);
    expect(h.port.writes, 0);
    h.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}

class Harness {
  Harness(
    this.account,
    this.port,
    this.controller,
    this.queue,
    this.key,
    this.ready,
  ) {
    restartFlow();
  }
  final AccountModule account;
  final PrivacyFixture port;
  final LocalPrivacyController controller;
  final StartupPromptQueue queue;
  final GlobalKey<NavigatorState> key;
  bool ready;
  int adjustments = 0;
  FirstUsePrivacyFlow? _flow;
  FirstUsePrivacyFlow get flow => _flow!;

  static Future<Harness> create(
    WidgetTester tester, {
    bool ready = true,
    bool? metadata = true,
  }) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final account = createAccountModule(
      InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
    );
    await account.initialize();
    final port = PrivacyFixture()..firstUse = metadata;
    final controller = LocalPrivacyController(port);
    final queue = StartupPromptQueue();
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [queue],
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppStrings.runtimeSupportedLocales(),
        localizationsDelegates: const [
          AppStringsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(),
      ),
    );
    await tester.pumpAndSettle();
    return Harness(account, port, controller, queue, key, ready);
  }

  void restartFlow() {
    _flow?.dispose();
    _flow = FirstUsePrivacyFlow(
      account: account,
      privacy: controller,
      queue: queue,
      ready: () => ready,
      onAdjust: () => adjustments++,
    )..wake();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  void dispose() {
    flow.dispose();
    queue.dispose();
    controller.dispose();
    account.dispose();
  }
}

class PrivacyFixture implements LocalPrivacyPort, PrivacyPublicationPort {
  final events = StreamController<void>.broadcast();
  LocalPrivacySnapshot snapshot = const LocalPrivacySnapshot(revision: 0);
  bool? firstUse = true;
  bool failSave = false;
  bool failRead = false;
  Completer<LocalPrivacySnapshot>? pendingSave;
  int writes = 0, applies = 0;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  bool get publicationSupported => true;
  @override
  Future<LocalPrivacySnapshot> read() async {
    if (failRead) throw StateError('fixture read failure');
    return snapshot;
  }

  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings settings) async {
    writes++;
    if (failSave) throw StateError('fixture save failure');
    if (pendingSave != null) return pendingSave!.future;
    if (!settings.publicationEnabled) firstUse = false;
    return snapshot = LocalPrivacySnapshot(
      revision: snapshot.revision + 1,
      savedAt: DateTime.now(),
      settings: settings,
    );
  }

  @override
  Future<PrivacyPublicationView> publication(
    String action, {
    int? revision,
  }) async {
    if (action == 'apply') {
      applies++;
      firstUse = false;
    }
    return PrivacyPublicationView(
      action == 'apply' ? 'applied' : 'inactive',
      firstUseRequired: firstUse,
    );
  }

  @override
  Future<void> close() => events.close();
}
