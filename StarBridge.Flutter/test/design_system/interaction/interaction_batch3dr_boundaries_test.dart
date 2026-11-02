import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/settings/help_support_action.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/in_memory_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_page.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/features/settings/privacy_live_sharing_panel.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';
import 'package:starbridge_flutter/features/settings/privacy_settings_page.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/settings/local_privacy_page_test.dart' as original;
import 'interaction_batch3do_test.dart' show act, loadFonts, scopedApp, size;

const _timeout = Timeout(Duration(seconds: 45));

// Bounded frame steps deliberately do not settle indeterminate save feedback.
Future<void> _frames(WidgetTester t, {int count = 12}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

class _Port extends original.MemoryPrivacy {
  _Port() {
    snapshot = LocalPrivacySnapshot(
      revision: 4,
      settings: LocalPrivacySettings.editorDefaults,
    );
  }

  final submitted = <LocalPrivacySettings>[];

  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings settings) {
    submitted.add(settings);
    return super.save(settings);
  }
}

class _StatusPort extends _Port implements PrivacyPublicationPort {
  _StatusPort() {
    snapshot = LocalPrivacySnapshot(
      revision: 4,
      settings: LocalPrivacySettings.editorDefaults.copyWith(
        publicationEnabled: true,
      ),
    );
  }

  bool failRead = false;
  Completer<PrivacyPublicationView>? pending;
  final requests = <String>[];

  @override
  bool get publicationSupported => true;

  @override
  Future<PrivacyPublicationView> publication(
    String action, {
    int? revision,
  }) async {
    requests.add(action);
    if (failRead) throw StateError('synthetic status unavailable');
    return pending?.future ?? const PrivacyPublicationView('inactive');
  }
}

class _Harness {
  _Harness(this.port, this.local, this.sync, this.combined);

  final _Port port;
  final LocalPrivacyController local;
  final SyncPrivacyModule sync;
  final bool combined;
  late BuildContext context;
  PrivacyPageDrafts? drafts;
  bool closed = false;

  static Future<_Harness> create(
    WidgetTester t,
    InteractionSuite suite, {
    bool combined = true,
  }) async {
    size(t, const Size(1280, 1000));
    final port = _Port();
    final local = LocalPrivacyController(port);
    final sync = createSyncPrivacyModule(
      InMemorySyncPrivacyAdapter.forReview(),
    );
    await sync.initialize();
    final h = _Harness(port, local, sync, combined);
    await t.pumpWidget(
      scopedApp(
        combined
            ? PrivacySettingsPage(localPrivacy: local, syncPrivacy: sync)
            : LocalPrivacyPage(controller: local),
        suite,
      ),
    );
    await _frames(t);
    h.context = t.element(find.byType(LocalPrivacyPage));
    if (combined) h.drafts = PrivacyDraftScope.of(h.context)!;
    expect(local.hasSaved, isTrue);
    expect(local.dirty, isFalse);
    expect(port.writes, 0);
    return h;
  }

  void editLocal() => local.edit(local.draft!.copyWith(roomFields: 0));

  Future<void> save(WidgetTester t) async {
    await t.tap(find.byKey(const Key('privacy-save')));
    await t.pump();
  }

  Future<void> close(WidgetTester t) async {
    if (closed) return;
    closed = true;
    await t.pumpWidget(const SizedBox.shrink());
    await _frames(t, count: 2);
    local.dispose();
    sync.dispose();
  }
}

StarBridgeActionButton _button(WidgetTester t, String key) {
  final target = find.byKey(Key(key));
  return t.widget<StarBridgeActionButton>(
    find
        .ancestor(of: target, matching: find.byType(StarBridgeActionButton))
        .first,
  );
}

Future<void> _activate(WidgetTester t, String key, String source) async {
  final target = find.byKey(Key(key));
  final adapter = t.widget<HelpSupportAction>(
    find.ancestor(of: target, matching: find.byType(HelpSupportAction)).first,
  );
  await act(t, target, source, (adapter.child as Text).data!);
}

void main() {
  setUpAll(loadFonts);

  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite status read wait belongs to controller identity as well as epoch',
      (t) async {
        size(t, const Size(1100, 1000));
        final oldPort = _StatusPort();
        final newPort = _StatusPort();
        final oldOwner = LocalPrivacyController(oldPort);
        final newOwner = LocalPrivacyController(newPort);
        final oldPending = Completer<PrivacyPublicationView>();
        final newPending = Completer<PrivacyPublicationView>();
        try {
          for (final owner in [oldOwner, newOwner]) {
            await owner.refresh();
          }
          for (final entry in [(oldOwner, oldPort), (newOwner, newPort)]) {
            entry.$2.failRead = true;
            await entry.$1.refreshPublication();
            await entry.$1.refreshPublication();
            entry.$2.failRead = false;
            expect(entry.$1.publicationReadFailures, 2);
          }
          expect(oldOwner.scopeEpoch, newOwner.scopeEpoch);
          const panelKey = Key('same-status-panel-element');
          await t.pumpWidget(
            scopedApp(
              PrivacyLiveSharingPanel(key: panelKey, controller: oldOwner),
              suite,
            ),
          );
          await _frames(t);
          final originalElement = t.element(find.byKey(panelKey));
          oldPort.pending = oldPending;
          await _activate(t, 'privacy-reapply', 'pointer');
          await _frames(t, count: 2);
          expect(find.byType(HelpSupportWaiting), findsOneWidget);
          expect(
            t
                .widget<HelpSupportWaiting>(find.byType(HelpSupportWaiting))
                .source,
            InteractionSource.pointer,
          );

          await t.pumpWidget(
            scopedApp(
              PrivacyLiveSharingPanel(key: panelKey, controller: newOwner),
              suite,
            ),
          );
          await _frames(t, count: 2);
          expect(t.element(find.byKey(panelKey)), same(originalElement));
          expect(find.byType(HelpSupportWaiting), findsNothing);

          final before = newPort.requests.length;
          newPort.pending = newPending;
          final duplicate = _button(t, 'privacy-reapply').onActivate!;
          await _activate(t, 'privacy-reapply', 'keyboard');
          await _frames(t, count: 2);
          final newWait = t.widget<HelpSupportWaiting>(
            find.byType(HelpSupportWaiting),
          );
          expect(newWait.source, InteractionSource.keyboard);
          expect(find.byType(SuiteProgressBar), findsNothing);
          duplicate(InteractionSource.pointer);
          await _frames(t, count: 2);
          expect(newPort.requests.skip(before), ['status']);
          expect(
            t.widget<HelpSupportWaiting>(find.byType(HelpSupportWaiting)).key,
            newWait.key,
          );
          expect(
            t
                .widget<HelpSupportWaiting>(find.byType(HelpSupportWaiting))
                .source,
            InteractionSource.keyboard,
          );

          oldPending.complete(
            PrivacyPublicationView('applied', revision: oldOwner.revision),
          );
          await _frames(t, count: 2);
          expect(find.byType(HelpSupportWaiting), findsOneWidget);
          expect(
            t.widget<HelpSupportWaiting>(find.byType(HelpSupportWaiting)).key,
            newWait.key,
          );
          expect(newOwner.publicationReadFailures, 2);
          newPending.complete(
            PrivacyPublicationView('applied', revision: newOwner.revision),
          );
          await _frames(t);
          expect(find.byType(HelpSupportWaiting), findsNothing);
          expect(newOwner.publicationReadFailures, 0);
          expect(oldPort.writes, 0);
          expect(newPort.writes, 0);
          expect(t.takeException(), isNull);
        } finally {
          if (!oldPending.isCompleted) {
            oldPending.complete(const PrivacyPublicationView('inactive'));
          }
          if (!newPending.isCompleted) {
            newPending.complete(const PrivacyPublicationView('inactive'));
          }
          await t.pumpWidget(const SizedBox.shrink());
          await _frames(t, count: 2);
          oldOwner.dispose();
          newOwner.dispose();
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite local wait listener retires old controller and captures new request source',
      (t) async {
        size(t, const Size(1280, 1000));
        final oldPort = _Port();
        final newPort = _Port();
        final oldOwner = LocalPrivacyController(oldPort);
        final newOwner = LocalPrivacyController(newPort);
        final oldPending = Completer<LocalPrivacySnapshot>();
        final newPending = Completer<LocalPrivacySnapshot>();
        try {
          await oldOwner.refresh();
          await newOwner.refresh();
          expect(oldOwner.scopeEpoch, newOwner.scopeEpoch);
          const pageKey = Key('same-local-privacy-element');
          await t.pumpWidget(
            scopedApp(
              LocalPrivacyPage(key: pageKey, controller: oldOwner),
              suite,
            ),
          );
          await _frames(t);
          final originalElement = t.element(find.byKey(pageKey));
          oldOwner.edit(oldOwner.draft!.copyWith(roomFields: 0));
          oldPort.pendingSave = oldPending;
          await t.pump();
          await _activate(t, 'privacy-save', 'keyboard');
          await _frames(t, count: 2);
          expect(oldPort.writes, 1);
          expect(
            t
                .widget<HelpSupportWaiting>(find.byType(HelpSupportWaiting))
                .source,
            InteractionSource.keyboard,
          );

          await t.pumpWidget(
            scopedApp(
              LocalPrivacyPage(key: pageKey, controller: newOwner),
              suite,
            ),
          );
          await _frames(t, count: 2);
          expect(t.element(find.byKey(pageKey)), same(originalElement));
          // Test-only introspection: the domain owner is final; do not add a
          // production API or weaken this explicit listener-retirement check.
          // ignore: invalid_use_of_protected_member
          expect(oldOwner.hasListeners, isFalse);
          expect(find.byType(HelpSupportWaiting), findsNothing);
          newOwner.edit(newOwner.draft!.copyWith(roomFields: 0));
          newPort.pendingSave = newPending;
          await t.pump();
          final duplicate = _button(t, 'privacy-save').onActivate!;
          await _activate(t, 'privacy-save', 'pointer');
          await _frames(t, count: 2);
          final newWait = t.widget<HelpSupportWaiting>(
            find.byType(HelpSupportWaiting),
          );
          expect(newWait.source, InteractionSource.pointer);
          expect(find.byType(SuiteProgressBar), findsOneWidget);
          duplicate(InteractionSource.keyboard);
          await _frames(t, count: 2);
          expect(newPort.writes, 1);
          expect(
            t
                .widget<HelpSupportWaiting>(find.byType(HelpSupportWaiting))
                .source,
            InteractionSource.pointer,
          );

          oldPending.complete(
            LocalPrivacySnapshot(
              revision: 5,
              settings: oldPort.submitted.single,
            ),
          );
          await _frames(t, count: 2);
          expect(find.byType(HelpSupportWaiting), findsOneWidget);
          expect(
            t.widget<HelpSupportWaiting>(find.byType(HelpSupportWaiting)).key,
            newWait.key,
          );
          expect(newOwner.saving, isTrue);
          newPending.complete(
            LocalPrivacySnapshot(
              revision: 5,
              settings: newPort.submitted.single,
            ),
          );
          await _frames(t);
          expect(find.byType(HelpSupportWaiting), findsNothing);
          expect(newOwner.dirty, isFalse);
          await t.pumpWidget(const SizedBox.shrink());
          await _frames(t, count: 2);
          // Test-only ChangeNotifier cleanup probes, not product access.
          // ignore: invalid_use_of_protected_member
          expect(oldOwner.hasListeners, isFalse);
          // ignore: invalid_use_of_protected_member
          expect(newOwner.hasListeners, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          if (!oldPending.isCompleted) {
            oldPending.complete(const LocalPrivacySnapshot(revision: 4));
          }
          if (!newPending.isCompleted) {
            newPending.complete(const LocalPrivacySnapshot(revision: 4));
          }
          await t.pumpWidget(const SizedBox.shrink());
          await _frames(t, count: 2);
          oldOwner.dispose();
          newOwner.dispose();
        }
      },
      timeout: _timeout,
    );

    for (final throws in [false, true]) {
      testWidgets(
        '$suite remote partial ${throws ? 'throw' : 'refusal'} preserves failed group and never replays acknowledged owners',
        (t) async {
          final h = await _Harness.create(t, suite);
          try {
            var firstCalls = 0;
            var secondCalls = 0;
            var reject = true;
            h.drafts!.edit('first-fixture-owner', false, true, (_) async {
              firstCalls++;
              return true;
            });
            h.drafts!.edit('second-fixture-owner', false, true, (_) async {
              secondCalls++;
              if (reject && throws) throw StateError('synthetic refusal');
              return !reject;
            });
            h.editLocal();
            await t.pump();
            await h.save(t);
            await _frames(t);
            expect(firstCalls, 1);
            expect(secondCalls, 1);
            expect(h.port.writes, 1);
            expect(h.local.dirty, isFalse);
            expect(h.local.draft!.roomFields, 0);
            expect(h.drafts!.failed, isTrue);
            expect(h.drafts!.dirty, isTrue);
            expect(h.drafts!.value('first-fixture-owner', false), isFalse);
            expect(h.drafts!.value('second-fixture-owner', false), isTrue);
            expect(_button(t, 'privacy-save').onActivate, isNotNull);

            reject = false;
            await h.save(t);
            await _frames(t);
            expect(firstCalls, 1);
            expect(secondCalls, 2);
            expect(h.port.writes, 1);
            expect(h.drafts!.dirty, isFalse);
            expect(h.drafts!.failed, isFalse);
            expect(t.takeException(), isNull);
          } finally {
            await h.close(t);
          }
        },
        timeout: _timeout,
      );
    }

    testWidgets(
      '$suite remote success and local refusal keep only local draft retryable',
      (t) async {
        final h = await _Harness.create(t, suite);
        try {
          var remoteCalls = 0;
          h.drafts!.edit('remote-fixture-owner', false, true, (_) async {
            remoteCalls++;
            return true;
          });
          h.editLocal();
          h.port.failure = const BridgeClientException(
            'privacy_local.write_failed',
          );
          await t.pump();
          await h.save(t);
          await _frames(t);
          expect(remoteCalls, 1);
          expect(h.drafts!.dirty, isFalse);
          expect(h.local.dirty, isTrue);
          expect(h.local.draft!.roomFields, 0);
          expect(h.local.errorKey, 'privacy.local.saveFailed');
          expect(h.port.writes, 1);
          h.port.failure = null;
          await h.save(t);
          await _frames(t);
          expect(remoteCalls, 1);
          expect(h.port.writes, 2);
          expect(h.local.dirty, isFalse);
          expect(h.local.errorKey, isNull);
          expect(t.takeException(), isNull);
        } finally {
          await h.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite pending remote blocks leave double submission discard and section changes',
      (t) async {
        final h = await _Harness.create(t, suite);
        final pending = Completer<bool>();
        try {
          var calls = 0;
          h.drafts!.edit('remote-fixture-owner', false, true, (_) {
            calls++;
            return pending.future;
          });
          h.editLocal();
          await t.pump();
          final oldSave = _button(t, 'privacy-save').onActivate!;
          await h.save(t);
          await _frames(t, count: 2);
          expect(calls, 1);
          expect(h.port.writes, 0);
          expect(_button(t, 'privacy-save').onActivate, isNull);
          expect(_button(t, 'privacy-discard').onActivate, isNull);
          oldSave(InteractionSource.pointer);
          await t.pump();
          expect(calls, 1);
          expect(await confirmLocalPrivacyLeave(h.context, h.local), isFalse);
          expect(find.byKey(const Key('privacy-leave-dialog')), findsNothing);
          await t.tap(find.byKey(const Key('privacy-section-account')));
          await _frames(t, count: 2);
          expect(find.byKey(const Key('local-privacy-page')), findsOneWidget);
          expect(h.local.dirty, isTrue);
          pending.complete(true);
          await _frames(t);
          expect(h.port.writes, 1);
          expect(h.local.dirty, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          if (!pending.isCompleted) pending.complete(false);
          await _frames(t, count: 2);
          await h.close(t);
        }
      },
      timeout: _timeout,
    );

    for (final invalidation in [
      'draft epoch',
      'local account',
      'page dispose',
    ]) {
      testWidgets(
        '$suite $invalidation during remote save prevents late local write',
        (t) async {
          final h = await _Harness.create(t, suite);
          final pending = Completer<bool>();
          try {
            var secondCalls = 0;
            h.drafts!.edit(
              'first-fixture-owner',
              false,
              true,
              (_) => pending.future,
            );
            h.drafts!.edit('second-fixture-owner', false, true, (_) async {
              secondCalls++;
              return true;
            });
            h.editLocal();
            await t.pump();
            await h.save(t);
            await _frames(t, count: 2);
            if (invalidation == 'draft epoch') {
              h.drafts!.discard();
            } else if (invalidation == 'local account') {
              h.port.snapshot = LocalPrivacySnapshot(
                revision: 19,
                settings: LocalPrivacySettings.editorDefaults.copyWith(
                  roomFields: 1,
                ),
              );
              h.port.events.add(null);
              await _frames(t, count: 2);
            } else {
              await t.pumpWidget(const SizedBox.shrink());
              await _frames(t, count: 2);
              expect(privacyPageLeaveGuards[h.local], isNull);
            }
            pending.complete(true);
            await _frames(t);
            expect(h.port.writes, 0);
            // Local account invalidation retains the independently owned remote
            // transaction; the page epoch is intentionally not synthesized here.
            expect(secondCalls, invalidation == 'local account' ? 1 : 0);
            if (invalidation == 'local account') {
              expect(h.local.revision, 19);
              expect(h.local.draft!.roomFields, 1);
              expect(h.local.dirty, isFalse);
            }
            expect(t.takeException(), isNull);
          } finally {
            if (!pending.isCompleted) pending.complete(false);
            await _frames(t, count: 2);
            await h.close(t);
          }
        },
        timeout: _timeout,
      );
    }

    testWidgets(
      '$suite late local save cannot overwrite refreshed account after remote success',
      (t) async {
        final h = await _Harness.create(t, suite);
        final pending = Completer<LocalPrivacySnapshot>();
        try {
          var remoteCalls = 0;
          h.drafts!.edit('remote-fixture-owner', false, true, (_) async {
            remoteCalls++;
            return true;
          });
          h.editLocal();
          h.port.pendingSave = pending;
          await t.pump();
          await h.save(t);
          await _frames(t, count: 2);
          expect(h.port.writes, 1);
          expect(remoteCalls, 1);
          h.port.snapshot = LocalPrivacySnapshot(
            revision: 27,
            settings: LocalPrivacySettings.editorDefaults.copyWith(
              roomFields: 4,
            ),
          );
          h.port.events.add(null);
          await _frames(t, count: 2);
          pending.complete(
            LocalPrivacySnapshot(
              revision: 5,
              settings: h.port.submitted.single,
            ),
          );
          await _frames(t);
          expect(h.local.revision, 27);
          expect(h.local.draft!.roomFields, 4);
          expect(h.local.dirty, isFalse);
          expect(h.port.writes, 1);
          expect(remoteCalls, 1);
          expect(t.takeException(), isNull);
        } finally {
          if (!pending.isCompleted) {
            pending.complete(const LocalPrivacySnapshot(revision: 4));
          }
          await _frames(t, count: 2);
          await h.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite combined leave cancel preserves both owners and explicit discard clears both',
      (t) async {
        final h = await _Harness.create(t, suite);
        try {
          var remoteCalls = 0;
          h.drafts!.edit('remote-fixture-owner', false, true, (_) async {
            remoteCalls++;
            return true;
          });
          h.editLocal();
          await t.pump();
          var leave = confirmLocalPrivacyLeave(h.context, h.local);
          await _frames(t);
          await t.tap(find.byKey(const Key('privacy-leave-cancel')));
          await _frames(t);
          expect(await leave, isFalse);
          expect(h.local.dirty, isTrue);
          expect(h.drafts!.dirty, isTrue);
          leave = confirmLocalPrivacyLeave(h.context, h.local);
          await _frames(t);
          await t.tap(find.byKey(const Key('privacy-leave-discard')));
          await _frames(t);
          expect(await leave, isTrue);
          expect(h.local.dirty, isFalse);
          expect(h.drafts!.dirty, isFalse);
          expect(h.port.writes, 0);
          expect(remoteCalls, 0);
          expect(t.takeException(), isNull);
        } finally {
          await h.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite combined leave save refusal stays dirty and later explicit retry succeeds',
      (t) async {
        final h = await _Harness.create(t, suite);
        try {
          h.editLocal();
          h.port.failure = const BridgeClientException(
            'privacy_local.write_failed',
          );
          await t.pump();
          var leave = confirmLocalPrivacyLeave(h.context, h.local);
          await _frames(t);
          await t.tap(find.byKey(const Key('privacy-leave-save')));
          await _frames(t);
          expect(await leave, isFalse);
          expect(h.local.dirty, isTrue);
          expect(h.port.writes, 1);
          h.port.failure = null;
          leave = confirmLocalPrivacyLeave(h.context, h.local);
          await _frames(t);
          await t.tap(find.byKey(const Key('privacy-leave-save')));
          await _frames(t);
          expect(await leave, isTrue);
          expect(h.local.dirty, isFalse);
          expect(h.port.writes, 2);
          expect(t.takeException(), isNull);
        } finally {
          await h.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite standalone pending local save forbids leave and ignores duplicate old callback',
      (t) async {
        final h = await _Harness.create(t, suite, combined: false);
        final pending = Completer<LocalPrivacySnapshot>();
        try {
          h.editLocal();
          h.port.pendingSave = pending;
          await t.pump();
          final oldSave = _button(t, 'privacy-save').onActivate!;
          await h.save(t);
          await _frames(t, count: 2);
          oldSave(InteractionSource.pointer);
          await t.pump();
          expect(h.port.writes, 1);
          expect(h.local.saving, isTrue);
          expect(_button(t, 'privacy-save').onActivate, isNull);
          expect(_button(t, 'privacy-discard').onActivate, isNull);
          expect(await confirmLocalPrivacyLeave(h.context, h.local), isFalse);
          expect(find.byKey(const Key('privacy-leave-dialog')), findsNothing);
          pending.complete(
            LocalPrivacySnapshot(
              revision: 5,
              settings: h.port.submitted.single,
            ),
          );
          await _frames(t);
          expect(h.local.dirty, isFalse);
          expect(await confirmLocalPrivacyLeave(h.context, h.local), isTrue);
          expect(t.takeException(), isNull);
        } finally {
          if (!pending.isCompleted) {
            pending.complete(const LocalPrivacySnapshot(revision: 4));
          }
          await _frames(t, count: 2);
          await h.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite standalone old leave confirmation never saves new account draft',
      (t) async {
        final h = await _Harness.create(t, suite, combined: false);
        try {
          h.editLocal();
          await t.pump();
          final leave = confirmLocalPrivacyLeave(h.context, h.local);
          await _frames(t);
          h.port.snapshot = LocalPrivacySnapshot(
            revision: 43,
            settings: LocalPrivacySettings.editorDefaults.copyWith(
              roomFields: 8,
            ),
          );
          h.port.events.add(null);
          await _frames(t, count: 2);
          await t.tap(find.byKey(const Key('privacy-leave-save')));
          await _frames(t);
          expect(await leave, isFalse);
          expect(h.port.writes, 0);
          expect(h.local.revision, 43);
          expect(h.local.draft!.roomFields, 8);
          expect(h.local.dirty, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          await h.close(t);
        }
      },
      timeout: _timeout,
    );
  }
}
