import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/features/settings/help_support_action.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/in_memory_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_page.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/settings/privacy_settings_page.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';

import '../../features/settings/local_privacy_page_test.dart' as original;
import 'interaction_batch3do_test.dart' as fixture;

Future<void> editorFrames(WidgetTester t, [int count = 10]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

class EditorPort extends original.ConfidencePrivacy {
  EditorPort() {
    snapshot = LocalPrivacySnapshot(
      revision: 5,
      settings: LocalPrivacySettings.editorDefaults,
    );
  }
  Completer<LocalPrivacySnapshot>? pendingRead;
  @override
  Future<LocalPrivacySnapshot> read() => pendingRead?.future ?? super.read();
}

Widget editorApp(
  Widget page,
  InteractionSuite suite, {
  bool light = false,
  bool reduce = false,
  double scale = 1,
  Locale locale = const Locale('zh', 'CN'),
}) {
  final app = fixture.scopedApp(
    page,
    suite,
    light: light,
    reduce: reduce,
    locale: locale,
  ) as MaterialApp;
  return RepaintBoundary(
    key: const Key('3dr-frame'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: app.locale,
      supportedLocales: app.supportedLocales,
      localizationsDelegates: app.localizationsDelegates,
      theme: app.theme,
      themeAnimationDuration: Duration.zero,
      home: app.home,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: app.builder!(context, child),
      ),
    ),
  );
}

StarBridgeActionButton editorButton(WidgetTester t, String key) =>
    t.widget<StarBridgeActionButton>(
      find
          .ancestor(
            of: find.byKey(Key(key)),
            matching: find.byType(StarBridgeActionButton),
          )
          .first,
    );

Future<void> editorAct(WidgetTester t, String key, String source) async {
  final target = find.byKey(Key(key));
  final adapter = t.widget<HelpSupportAction>(
    find.ancestor(of: target, matching: find.byType(HelpSupportAction)).first,
  );
  await fixture.act(t, target, source, (adapter.child as Text).data!);
}

void main() {
  setUpAll(fixture.loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source scope switches and section track retain immediate draft edits',
        (t) async {
          fixture.size(t, const Size(1200, 1000));
          final semantics = t.ensureSemantics();
          final p = EditorPort();
          final c = LocalPrivacyController(p);
          final sync = createSyncPrivacyModule(
            InMemorySyncPrivacyAdapter.forReview(),
          );
          await sync.initialize();
          try {
            await t.pumpWidget(
              editorApp(
                PrivacySettingsPage(localPrivacy: c, syncPrivacy: sync),
                suite,
              ),
            );
            await editorFrames(t);
            final confidence = find.byKey(
              const Key('privacy-location-confidence'),
            );
            final label = t.widget<StarBridgeSwitch>(confidence).label;
            expect(find.text(label), findsOneWidget);
            expect(
              find.text(t.widget<StarBridgeSwitch>(confidence).subtitle!),
              findsOneWidget,
            );
            await fixture.act(t, confidence, source, label);
            await t.pump();
            expect(c.draft!.effectiveHideLowConfidenceLocation, isFalse);
            expect(p.writes, 0);
            final account = find.byKey(const Key('privacy-section-account'));
            final row = t.widget<StarBridgeActionRow>(
              find
                  .ancestor(
                    of: account,
                    matching: find.byType(StarBridgeActionRow),
                  )
                  .first,
            );
            await fixture.act(t, account, source, row.semanticLabel!);
            await t.pump();
            final track = t.widget<SuiteSelectionTrack>(
              find.byType(SuiteSelectionTrack).first,
            );
            expect(track.selected, 1);
            expect(
              track.changeSource,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(c.draft!.effectiveHideLowConfidenceLocation, isFalse);
            expect(p.writes, 0);
            expect(find.byKey(const Key('privacy-leave-dialog')), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox.shrink());
            await editorFrames(t, 2);
            c.dispose();
            sync.dispose();
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );

      for (final combined in [false, true]) {
        for (final choice in ['save', 'discard']) {
          testWidgets(
            '$suite $source combined=$combined leave $choice forwards confirming origin and original owner result',
            (t) async {
              fixture.size(t, const Size(1100, 900));
              final semantics = t.ensureSemantics();
              final p = EditorPort();
              final c = LocalPrivacyController(p);
              final sync = createSyncPrivacyModule(
                InMemorySyncPrivacyAdapter.forReview(),
              );
              await sync.initialize();
              final pending = Completer<LocalPrivacySnapshot>();
              InteractionSource? completed;
              bool? result;
              try {
                await t.pumpWidget(
                  editorApp(
                    combined
                        ? PrivacySettingsPage(
                            localPrivacy: c,
                            syncPrivacy: sync,
                          )
                        : LocalPrivacyPage(controller: c),
                    suite,
                  ),
                );
                await editorFrames(t);
                c.edit(c.draft!.copyWith(roomFields: 0));
                if (choice == 'save') p.pendingSave = pending;
                await t.pump();
                final context = t.element(find.byType(LocalPrivacyPage));
                final command = runStarBridgeActivation<void>(
                  InteractionSource.pointer,
                  () async {
                    result = await confirmLocalPrivacyLeave(context, c);
                    completed = currentStarBridgeActivationSource;
                  },
                );
                await editorFrames(t);
                await editorAct(t, 'privacy-leave-$choice', source);
                await editorFrames(t);
                if (choice == 'save') {
                  expect(c.saving, isTrue);
                  expect(result, isNull);
                  expect(p.writes, 1);
                  final wait = t.widget<HelpSupportWaiting>(
                    find.byType(HelpSupportWaiting).last,
                  );
                  expect(
                    wait.source,
                    source == 'pointer'
                        ? InteractionSource.pointer
                        : InteractionSource.keyboard,
                  );
                  pending.complete(
                    LocalPrivacySnapshot(revision: 6, settings: c.draft),
                  );
                  await editorFrames(t);
                }
                await command;
                expect(result, isTrue);
                expect(
                  completed,
                  source == 'pointer'
                      ? InteractionSource.pointer
                      : InteractionSource.keyboard,
                );
                expect(c.dirty, isFalse);
                expect(p.writes, choice == 'save' ? 1 : 0);
                expect(t.takeException(), isNull);
              } finally {
                if (!pending.isCompleted) {
                  pending.complete(const LocalPrivacySnapshot(revision: 5));
                }
                await t.pumpWidget(const SizedBox.shrink());
                await editorFrames(t, 2);
                c.dispose();
                sync.dispose();
                semantics.dispose();
              }
            },
            timeout: const Timeout(Duration(seconds: 45)),
          );
        }
      }
      for (final combined in [false, true]) {
        testWidgets(
          '$suite $source combined=$combined save wait freezes actual origin and preserves pending owner',
          (t) async {
            fixture.size(t, const Size(1000, 900));
            final semantics = t.ensureSemantics();
            final p = EditorPort();
            final c = LocalPrivacyController(p);
            final sync = createSyncPrivacyModule(
              InMemorySyncPrivacyAdapter.forReview(),
            );
            await sync.initialize();
            final page = combined
                ? PrivacySettingsPage(localPrivacy: c, syncPrivacy: sync)
                : LocalPrivacyPage(controller: c);
            final pending = Completer<LocalPrivacySnapshot>();
            try {
              await t.pumpWidget(editorApp(page, suite));
              await editorFrames(t);
              c.edit(c.draft!.copyWith(roomFields: 0));
              p.pendingSave = pending;
              await t.pump();
              final old = editorButton(t, 'privacy-save').onActivate!;
              await editorAct(t, 'privacy-save', source);
              await editorFrames(t, 2);
              expect(p.writes, 1);
              expect(c.saving, isTrue);
              expect(c.dirty, isTrue);
              final wait = t.widget<HelpSupportWaiting>(
                find.byType(HelpSupportWaiting).last,
              );
              expect(
                wait.source,
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              expect(
                find.byType(SuiteProgressBar),
                source == 'pointer' ? findsOneWidget : findsNothing,
              );
              final key = wait.key;
              old(InteractionSource.pointer);
              await t.pump();
              expect(p.writes, 1);
              expect(
                t
                    .widget<HelpSupportWaiting>(
                      find.byType(HelpSupportWaiting).last,
                    )
                    .key,
                key,
              );
              expect(
                t
                    .widget<HelpSupportWaiting>(
                      find.byType(HelpSupportWaiting).last,
                    )
                    .source,
                wait.source,
              );
              expect(editorButton(t, 'privacy-save').onActivate, isNull);
              expect(editorButton(t, 'privacy-discard').onActivate, isNull);
              await t.pumpWidget(editorApp(page, suite, reduce: true));
              await editorFrames(t, 2);
              expect(find.byType(SuiteProgressBar), findsNothing);
              expect(p.writes, 1);
              expect(c.saving, isTrue);
              pending.complete(
                LocalPrivacySnapshot(revision: 6, settings: c.draft),
              );
              await editorFrames(t);
              expect(c.dirty, isFalse);
              expect(c.hasSaved, isTrue);
              expect(c.revision, 6);
              expect(find.byType(HelpSupportWaiting), findsNothing);
              expect(t.takeException(), isNull);
            } finally {
              if (!pending.isCompleted) {
                pending.complete(const LocalPrivacySnapshot(revision: 5));
              }
              await t.pumpWidget(const SizedBox.shrink());
              await editorFrames(t, 2);
              c.dispose();
              sync.dispose();
              semantics.dispose();
            }
          },
          timeout: const Timeout(Duration(seconds: 45)),
        );
      }

      testWidgets(
        '$suite $source leave confirmation propagates final source to outer navigation command',
        (t) async {
          fixture.size(t, const Size(1100, 900));
          final semantics = t.ensureSemantics();
          final p = EditorPort();
          final c = LocalPrivacyController(p);
          final sync = createSyncPrivacyModule(
            InMemorySyncPrivacyAdapter.forReview(),
          );
          await sync.initialize();
          InteractionSource? completedSource;
          bool? result;
          try {
            await t.pumpWidget(
              editorApp(
                PrivacySettingsPage(localPrivacy: c, syncPrivacy: sync),
                suite,
              ),
            );
            await editorFrames(t);
            c.edit(c.draft!.copyWith(roomFields: 0));
            await t.pump();
            final context = t.element(find.byType(LocalPrivacyPage));
            final command = runStarBridgeActivation<void>(
              InteractionSource.pointer,
              () async {
                result = await confirmLocalPrivacyLeave(context, c);
                completedSource = currentStarBridgeActivationSource;
              },
            );
            await editorFrames(t);
            expect(
              ModalRoute.of(
                t.element(find.byKey(const Key('privacy-leave-dialog'))),
              ),
              isA<StarBridgeDialogRoute<String>>(),
            );
            await editorAct(t, 'privacy-leave-cancel', source);
            await t.pump();
            await editorFrames(t);
            await command;
            expect(result, isFalse);
            expect(c.dirty, isTrue);
            expect(p.writes, 0);
            expect(
              completedSource,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox.shrink());
            await editorFrames(t, 2);
            c.dispose();
            sync.dispose();
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }

    testWidgets(
      '$suite initial read and failed read retry remain original requests',
      (t) async {
        fixture.size(t, const Size(1000, 900));
        final p = EditorPort();
        final c = LocalPrivacyController(p);
        final read = Completer<LocalPrivacySnapshot>();
        p.pendingRead = read;
        try {
          await t.pumpWidget(editorApp(LocalPrivacyPage(controller: c), suite));
          await editorFrames(t, 2);
          expect(find.byType(HelpSupportWaiting), findsOneWidget);
          expect(find.byType(SuiteProgressBar), findsOneWidget);
          expect(p.writes, 0);
          read.completeError(StateError('synthetic read unavailable'));
          await editorFrames(t);
          expect(find.byKey(const Key('privacy-read-retry')), findsOneWidget);
          expect(c.draft, isNull);
          p.pendingRead = null;
          await editorAct(t, 'privacy-read-retry', 'keyboard');
          await editorFrames(t);
          expect(c.status, LocalPrivacyStatus.ready);
          expect(p.writes, 0);
          expect(c.draft, isNotNull);
          expect(t.takeException(), isNull);
        } finally {
          if (!read.isCompleted) {
            read.complete(const LocalPrivacySnapshot(revision: 5));
          }
          await t.pumpWidget(const SizedBox.shrink());
          await editorFrames(t, 2);
          c.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
