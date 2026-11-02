import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/first_use_privacy_flow.dart';
import 'package:starbridge_flutter/app/runtime/startup_prompt_queue.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/first_use_privacy_flow_test.dart' as original;
import 'interaction_batch3do_test.dart' show act, loadFonts, scopedApp, size;

const _dialog = Key('first-privacy-choice-dialog');
const _timeout = Timeout(Duration(seconds: 45));

/// Advance real frames, including route completion and prompt quiet periods.
/// Never settle an indeterminate pending-operation indicator.
Future<void> _frames(WidgetTester t, {int count = 14}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

class _Port extends original.PrivacyFixture {
  final calls = <String>[];
  final submitted = <LocalPrivacySettings>[];
  Completer<PrivacyPublicationView>? pendingApply;
  Completer<PrivacyPublicationView>? pendingStatus;
  PrivacyPublicationView? applyResult;

  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings settings) {
    submitted.add(settings);
    return super.save(settings);
  }

  @override
  Future<PrivacyPublicationView> publication(
    String action, {
    int? revision,
  }) async {
    calls.add(action);
    if (action == 'apply' && (pendingApply != null || applyResult != null)) {
      applies++;
      final pending = pendingApply;
      pendingApply = null;
      return pending != null ? pending.future : applyResult!;
    }
    if (action == 'status' && pendingStatus != null) {
      final pending = pendingStatus!;
      pendingStatus = null;
      return pending.future;
    }
    return super.publication(action, revision: revision);
  }
}

class _FlowHarness {
  _FlowHarness(this.account, this.port, this.privacy, this.queue, this.key) {
    flow = FirstUsePrivacyFlow(
      account: account,
      privacy: privacy,
      queue: queue,
      ready: () => true,
      onAdjust: () {
        adjustments.add(currentStarBridgeActivationSource);
        completedSource = captureStarBridgeActivationSource();
      },
    )..wake();
  }

  final AccountModule account;
  final _Port port;
  final LocalPrivacyController privacy;
  final StartupPromptQueue queue;
  final GlobalKey<NavigatorState> key;
  late final FirstUsePrivacyFlow flow;
  final adjustments = <InteractionSource>[];
  ValueGetter<InteractionSource>? completedSource;

  static Widget _app(
    GlobalKey<NavigatorState> key,
    StartupPromptQueue queue,
    InteractionSuite suite, {
    bool light = false,
    bool reduce = false,
  }) {
    final base = scopedApp(
      const SizedBox(),
      suite,
      light: light,
      reduce: reduce,
    ) as MaterialApp;
    return MaterialApp(
      navigatorKey: key,
      navigatorObservers: [queue],
      theme: base.theme,
      themeAnimationDuration: Duration.zero,
      builder: base.builder,
      locale: base.locale,
      supportedLocales: base.supportedLocales,
      localizationsDelegates: base.localizationsDelegates,
      home: const Scaffold(),
    );
  }

  Future<void> rebuild(
    WidgetTester t,
    InteractionSuite suite, {
    required bool light,
    required bool reduce,
  }) => t.pumpWidget(_app(key, queue, suite, light: light, reduce: reduce));

  static Future<_FlowHarness> create(
    WidgetTester t,
    InteractionSuite suite, {
    bool? metadata = true,
  }) async {
    size(t, const Size(1000, 800));
    final account = createAccountModule(
      InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
    );
    await account.initialize();
    final port = _Port()..firstUse = metadata;
    final privacy = LocalPrivacyController(port);
    final queue = StartupPromptQueue();
    final key = GlobalKey<NavigatorState>();
    // Reuse the real-theme fixture without changing its public API or the
    // original flow tests. The observer is the production prompt queue.
    await t.pumpWidget(_app(key, queue, suite));
    await _frames(t, count: 2);
    final h = _FlowHarness(account, port, privacy, queue, key);
    await _frames(t);
    return h;
  }

  Future<void> close(WidgetTester t) async {
    flow.dispose();
    queue.dispose();
    privacy.dispose();
    account.dispose();
    await t.pumpWidget(const SizedBox());
    await _frames(t, count: 2);
  }
}

Future<void> _choose(WidgetTester t, String source, {bool accept = true}) =>
    act(
      t,
      find.byKey(
        Key(accept ? 'first-privacy-accept' : 'first-privacy-decline'),
      ),
      source,
      accept ? '启用状态共享' : '暂不开启',
    );

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite queued first-use route follows live suite palette and reduced motion during pending save',
      (t) async {
        final h = await _FlowHarness.create(t, suite);
        try {
          final before = InteractionScope.of(t.element(find.byKey(_dialog)));
          expect(before.suite, suite);
          expect(before.palette.brightness, Brightness.dark);
          expect(before.reduceMotion, isFalse);
          final route = ModalRoute.of(
            t.element(find.byKey(_dialog)),
          ) as StarBridgeDialogRoute<bool>;
          final save = Completer<LocalPrivacySnapshot>();
          h.port.pendingSave = save;
          await _choose(t, 'pointer');
          await _frames(t, count: 2);
          expect(find.byType(HelpSupportWaiting), findsOneWidget);
          final next = InteractionSuite
              .values[(suite.index + 1) % InteractionSuite.values.length];
          // Keep the exact Navigator, observer, controller and account. This
          // changes live app configuration rather than replacing the prompt.
          await h.rebuild(t, next, light: true, reduce: true);
          await t.pump(const Duration(milliseconds: 16));
          final after = InteractionScope.of(t.element(find.byKey(_dialog)));
          expect(after.suite, next);
          expect(after.palette.brightness, Brightness.light);
          expect(after.reduceMotion, isTrue);
          expect(ModalRoute.of(t.element(find.byKey(_dialog))), same(route));
          expect(route.animation!.value, 1);
          expect(find.byType(HelpSupportWaiting), findsOneWidget);
          expect(find.byType(SuiteProgressBar), findsNothing);
          expect(h.port.writes, 1);
          expect(h.port.applies, 0);
          save.complete(
            LocalPrivacySnapshot(
              revision: 1,
              settings: h.port.submitted.single,
            ),
          );
          await _frames(t);
          expect(find.byKey(_dialog), findsNothing);
          expect(h.port.writes, 1);
          expect(h.port.applies, 1);
          expect(h.adjustments, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await h.close(t);
        }
      },
      timeout: _timeout,
    );

    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source adjustment preserves actual source without recording consent',
        (t) async {
          final semantics = t.ensureSemantics();
          final h = await _FlowHarness.create(t, suite);
          try {
            expect(find.byKey(_dialog), findsOneWidget);
            expect(
              ModalRoute.of(t.element(find.byKey(_dialog))),
              isA<StarBridgeDialogRoute<bool>>(),
            );
            await act(
              t,
              find.byKey(const Key('first-privacy-adjust')),
              source,
              '调整共享范围',
            );
            await _frames(t);
            expect(h.adjustments, [
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            ]);
            expect(h.completedSource, isNotNull);
            expect(h.completedSource!(), InteractionSource.programmatic);
            expect(h.port.writes, 0);
            expect(h.port.applies, 0);
            expect(h.port.calls, ['status']);
            expect(find.byKey(_dialog), findsNothing);
            h.flow.wake();
            await _frames(t);
            expect(find.byKey(_dialog), findsNothing);
            expect(h.adjustments, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            await h.close(t);
            semantics.dispose();
          }
        },
        timeout: _timeout,
      );
    }

    for (final accept in [true, false]) {
      testWidgets(
        '$suite ${accept ? 'accept applies' : 'decline checks status'} only after authoritative save',
        (t) async {
          final h = await _FlowHarness.create(t, suite);
          try {
            final save = Completer<LocalPrivacySnapshot>();
            final publication = Completer<PrivacyPublicationView>();
            h.port.pendingSave = save;
            if (accept) {
              h.port.pendingApply = publication;
            } else {
              h.port.pendingStatus = publication;
            }
            final previousCalls = h.port.calls.length;
            await _choose(t, 'pointer', accept: accept);
            await _frames(t, count: 2);
            expect(h.port.writes, 1);
            expect(h.port.submitted.single.publicationEnabled, accept);
            expect(h.port.submitted.single.fleetFields, 0);
            expect(h.port.submitted.single.roomFields, 15);
            expect(h.port.calls, hasLength(previousCalls));
            expect(find.byKey(_dialog), findsOneWidget);
            expect(find.byType(HelpSupportWaiting), findsOneWidget);
            save.complete(
              LocalPrivacySnapshot(
                revision: 1,
                settings: h.port.submitted.single,
              ),
            );
            await _frames(t, count: 2);
            expect(h.port.calls.last, accept ? 'apply' : 'status');
            expect(h.port.applies, accept ? 1 : 0);
            expect(find.byKey(_dialog), findsOneWidget);
            expect(find.byType(HelpSupportWaiting), findsOneWidget);
            expect(h.adjustments, isEmpty);
            publication.complete(
              PrivacyPublicationView(
                accept ? 'applied' : 'inactive',
                firstUseRequired: false,
              ),
            );
            await _frames(t);
            expect(find.byKey(_dialog), findsNothing);
            expect(h.port.calls, hasLength(previousCalls + 1));
            expect(h.port.writes, 1);
            expect(h.adjustments, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await h.close(t);
          }
        },
        timeout: _timeout,
      );
    }

    testWidgets(
      '$suite unknown Host metadata neither implies consent nor optimistic apply completion',
      (t) async {
        final h = await _FlowHarness.create(t, suite, metadata: null);
        try {
          expect(find.byKey(_dialog), findsNothing);
          expect(h.port.writes, 0);
          expect(h.port.applies, 0);
          h.port.firstUse = true;
          await h.privacy.refresh();
          h.flow.wake();
          await _frames(t);
          expect(find.byKey(_dialog), findsOneWidget);
          final secondCheck = Completer<PrivacyPublicationView>();
          h.port.applyResult = const PrivacyPublicationView(
            'applied',
            firstUseRequired: null,
          );
          h.port.pendingStatus = secondCheck;
          final calls = h.port.calls.length;
          await _choose(t, 'pointer');
          await _frames(t, count: 3);
          expect(h.port.calls.sublist(calls), ['apply', 'status']);
          expect(h.port.writes, 1);
          expect(h.port.applies, 1);
          expect(find.byKey(_dialog), findsOneWidget);
          expect(find.byType(HelpSupportWaiting), findsOneWidget);
          expect(h.adjustments, isEmpty);
          secondCheck.complete(
            const PrivacyPublicationView('applied', firstUseRequired: false),
          );
          await _frames(t);
          expect(find.byKey(_dialog), findsNothing);
          expect(h.port.calls.sublist(calls), ['apply', 'status']);
          expect(h.adjustments, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await h.close(t);
        }
      },
      timeout: _timeout,
    );

    for (final stage in ['save', 'apply', 'status']) {
      for (final logout in [false, true]) {
        testWidgets(
          '$suite $stage ${logout ? 'logout' : 'invalidation'} retires only its prompt and rejects late acknowledgement',
          (t) async {
            final h = await _FlowHarness.create(t, suite);
            try {
              final save = Completer<LocalPrivacySnapshot>();
              final publication = Completer<PrivacyPublicationView>();
              if (stage == 'save') {
                h.port.pendingSave = save;
              } else if (stage == 'apply') {
                h.port.pendingApply = publication;
              } else {
                h.port.applyResult = const PrivacyPublicationView(
                  'applied',
                  firstUseRequired: null,
                );
                h.port.pendingStatus = publication;
              }
              await _choose(t, 'pointer');
              await _frames(t, count: 3);
              expect(find.byType(HelpSupportWaiting), findsOneWidget);
              expect(h.port.writes, 1);
              expect(h.port.applies, stage == 'save' ? 0 : 1);
              final manual = showDialog<void>(
                context: h.key.currentContext!,
                builder: (_) =>
                    const AlertDialog(title: Text('Unrelated manual route')),
              );
              await _frames(t, count: 4);
              h.port.events.add(null);
              if (logout) await h.account.logout();
              await _frames(t, count: 4);
              expect(find.text('Unrelated manual route'), findsOneWidget);
              expect(find.byKey(_dialog), findsNothing);
              expect(h.adjustments, isEmpty);
              if (stage == 'save') {
                save.complete(
                  LocalPrivacySnapshot(
                    revision: 1,
                    settings: h.port.submitted.single,
                  ),
                );
              } else {
                publication.complete(
                  const PrivacyPublicationView(
                    'stale-accepted',
                    firstUseRequired: false,
                  ),
                );
              }
              await _frames(t, count: 4);
              expect(find.text('Unrelated manual route'), findsOneWidget);
              expect(find.byKey(_dialog), findsNothing);
              expect(h.adjustments, isEmpty);
              expect(h.port.writes, 1);
              expect(h.port.applies, stage == 'save' ? 0 : 1);
              expect(h.privacy.publicationView.state, isNot('stale-accepted'));
              h.key.currentState!.pop();
              await manual;
              expect(t.takeException(), isNull);
            } finally {
              await h.close(t);
            }
          },
          timeout: _timeout,
        );
      }
    }
  }
}
