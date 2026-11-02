import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/in_memory_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_models.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_page.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_port.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3do_test.dart' show loadFonts, scopedApp, size;

const _timeout = Timeout(Duration(seconds: 45));
const _shipKey = Key('privacy-friends-ship');
const _realtimeKey = Key('privacy-realtime-sync');

Future<void> _frames(WidgetTester t, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// The actual review adapter supplies initial values and normal revisions.
/// Only explicit read/write gates and failures belong to this test transport.
class _Port implements SyncPrivacyPort {
  final inner = InMemorySyncPrivacyAdapter.forReview();
  final events = StreamController<void>.broadcast();
  final updates = <(SyncPrivacySettingsValue, int)>[];
  int reads = 0;
  Object? writeError;
  SyncPrivacyFailure? writeFailure;
  SyncPrivacySnapshot? nextRead;
  Completer<SyncPrivacySnapshot>? pendingRead;
  Completer<SyncPrivacyWriteResult>? pendingWrite;

  @override
  Stream<void> get invalidations => events.stream;

  @override
  Future<SyncPrivacySnapshot> read() {
    reads++;
    return pendingRead?.future ??
        (nextRead == null ? inner.read() : Future.value(nextRead!));
  }

  @override
  Future<SyncPrivacyWriteResult> update(
    SyncPrivacySettingsValue settings, {
    required int expectedRevision,
  }) async {
    updates.add((settings, expectedRevision));
    if (writeError != null) throw writeError!;
    if (writeFailure case final failure?) {
      return SyncPrivacyWriteResult.failed(failure);
    }
    return pendingWrite?.future ??
        inner.update(settings, expectedRevision: expectedRevision);
  }

  @override
  Future<void> close() async {
    await events.close();
    await inner.close();
  }
}

class _Harness {
  _Harness(this.port, this.module, this.suite, this.drafts);

  final _Port port;
  final SyncPrivacyModule module;
  final InteractionSuite suite;
  final PrivacyPageDrafts? drafts;
  bool closed = false;

  Widget page({SyncPrivacyModule? owner}) {
    Widget result = SyncPrivacyPage(
      key: const Key('same-sync-privacy-element'),
      module: owner ?? module,
    );
    if (drafts != null) {
      result = PrivacyDraftScope(drafts: drafts!, child: result);
    }
    return scopedApp(result, suite);
  }

  static Future<_Harness> create(
    WidgetTester t,
    InteractionSuite suite, {
    bool drafted = false,
  }) async {
    size(t, const Size(1280, 1100));
    final port = _Port();
    final module = createSyncPrivacyModule(port);
    await module.initialize();
    final h = _Harness(
      port,
      module,
      suite,
      drafted ? PrivacyPageDrafts() : null,
    );
    await t.pumpWidget(h.page());
    await _frames(t);
    expect(port.reads, 1);
    expect(port.updates, isEmpty);
    expect(module.projection.value.revision, 7);
    return h;
  }

  Future<void> close(WidgetTester t) async {
    if (closed) return;
    closed = true;
    await t.pumpWidget(const SizedBox.shrink());
    await _frames(t, count: 2);
    module.dispose();
    drafts?.dispose();
  }
}

Future<void> _toggle(WidgetTester t, Key key) async {
  final target = find.byKey(key);
  await t.ensureVisible(target);
  await t.pump();
  await t.tap(target);
  await t.pump();
}

StarBridgeSwitch _switch(WidgetTester t, Key key) => t.widget<StarBridgeSwitch>(
  find
      .ancestor(of: find.byKey(key), matching: find.byType(StarBridgeSwitch))
      .first,
);

SyncPrivacySnapshot _receipt(_Port port, {int revision = 8}) =>
    SyncPrivacySnapshot.available(
      revision: revision,
      settings: port.updates.last.$1,
    );

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final barrier in [
      'account new revision',
      'account same revision',
      'module replacement',
      'page unmount',
      'draft epoch',
    ]) {
      testWidgets(
        '$suite stale pause lease $barrier rejects confirmation rather than submitting old choices',
        (t) async {
          final h = await _Harness.create(
            t,
            suite,
            drafted: barrier == 'draft epoch',
          );
          final newPort = _Port();
          final newModule = createSyncPrivacyModule(newPort);
          try {
            if (barrier == 'draft epoch') {
              await _toggle(t, _shipKey);
              await _frames(t, count: 2);
              expect(h.drafts!.dirty, isTrue);
            }
            await _toggle(t, _realtimeKey);
            await _frames(t);
            expect(
              find.byKey(const Key('sync-privacy-pause-confirm')),
              findsOneWidget,
            );
            expect(h.port.updates, isEmpty);
            if (barrier.startsWith('account')) {
              if (barrier == 'account new revision') {
                final old = h.module.projection.value.settings!;
                h.port.nextRead = SyncPrivacySnapshot.available(
                  revision: 37,
                  settings: old.copyWith(
                    friendDefaults: old.friendDefaults.copyWith(
                      presence: false,
                      serverDetails: true,
                    ),
                  ),
                );
              }
              h.port.events.add(null);
              await _frames(t);
              expect(h.port.reads, 2);
              expect(
                h.module.projection.value.revision,
                barrier == 'account new revision' ? 37 : 7,
              );
            } else if (barrier == 'module replacement') {
              await newModule.initialize();
              expect(newModule.projection.value.revision, 7);
              await t.pumpWidget(h.page(owner: newModule));
              await _frames(t, count: 2);
            } else if (barrier == 'page unmount') {
              // Keep the same MaterialApp/Navigator and its outstanding modal;
              // remove only the owning page, as real destination changes do.
              await t.pumpWidget(
                scopedApp(const Text('other destination'), suite),
              );
              await _frames(t, count: 2);
              expect(
                find.byType(SyncPrivacyPage, skipOffstage: false),
                findsNothing,
              );
            } else {
              h.drafts!.discard();
              await _frames(t, count: 2);
              expect(h.drafts!.dirty, isFalse);
            }

            // A correct presentation may retire its own stale route, or leave
            // it open but reject its stale result. Either must prevent writes.
            final confirm = find.byKey(const Key('sync-privacy-pause-confirm'));
            if (confirm.evaluate().isNotEmpty) {
              await t.tap(confirm);
            }
            await _frames(t);
            expect(h.port.updates, isEmpty);
            expect(newPort.updates, isEmpty);
            expect(
              h.module.projection.value.settings!.realtimeSyncEnabled,
              isTrue,
            );
            if (h.drafts != null) {
              expect(h.drafts!.dirty, isFalse);
              expect(h.drafts!.failed, isFalse);
            }
            expect(t.takeException(), isNull);
          } finally {
            await h.close(t);
            newModule.dispose();
          }
        },
        timeout: _timeout,
      );
    }

    testWidgets(
      '$suite unchanged pause lease allows confirmation after same revision refresh',
      (t) async {
        final h = await _Harness.create(t, suite);
        try {
          await _toggle(t, _realtimeKey);
          await _frames(t);
          await h.module.refresh();
          await _frames(t, count: 2);
          expect(h.module.projection.value.revision, 7);
          expect(h.port.reads, 2);
          expect(h.port.updates, isEmpty);
          await t.tap(find.byKey(const Key('sync-privacy-pause-confirm')));
          await _frames(t);
          expect(h.port.updates, hasLength(1));
          expect(h.port.updates.single.$2, 7);
          expect(h.module.projection.value.revision, 8);
          expect(
            h.module.projection.value.settings!.realtimeSyncEnabled,
            isFalse,
          );
          expect(t.takeException(), isNull);
        } finally {
          await h.close(t);
        }
      },
      timeout: _timeout,
    );

    for (final choice in ['cancel', 'accept', 'barrier null', 'escape null']) {
      testWidgets(
        '$suite realtime pause $choice never publishes an optimistic choice',
        (t) async {
          final h = await _Harness.create(t, suite);
          final pending = Completer<SyncPrivacyWriteResult>();
          try {
            final saved = h.module.projection.value.settings!;
            await _toggle(t, _realtimeKey);
            await _frames(t);
            expect(
              find.byKey(const Key('sync-privacy-pause-confirm')),
              findsOneWidget,
            );
            expect(h.port.updates, isEmpty);
            expect(h.module.projection.value.settings, same(saved));
            expect(saved.realtimeSyncEnabled, isTrue);
            if (choice == 'cancel') {
              await t.tap(find.byKey(const Key('sync-privacy-pause-cancel')));
            } else if (choice == 'barrier null') {
              await t.tapAt(const Offset(3, 3));
            } else if (choice == 'escape null') {
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
            } else {
              h.port.pendingWrite = pending;
              await t.tap(find.byKey(const Key('sync-privacy-pause-confirm')));
            }
            await _frames(t);
            if (choice == 'accept') {
              expect(h.port.updates, hasLength(1));
              expect(h.port.updates.single.$2, 7);
              expect(h.port.updates.single.$1.realtimeSyncEnabled, isFalse);
              expect(
                h.port.updates.single.$1.friendDefaults,
                same(saved.friendDefaults),
              );
              expect(
                h.port.updates.single.$1.eventSharing,
                same(saved.eventSharing),
              );
              expect(h.port.updates.single.$1.social, same(saved.social));
              expect(h.module.projection.value.settings, same(saved));
              expect(
                h.module.projection.value.operation,
                SyncPrivacyOperation.saving,
              );
              expect(_switch(t, _realtimeKey).value, isTrue);
              expect(_switch(t, _realtimeKey).onChanged, isNull);
              pending.complete(
                SyncPrivacyWriteResult.completed(_receipt(h.port)),
              );
              await _frames(t);
              expect(h.module.projection.value.revision, 8);
              expect(_switch(t, _realtimeKey).value, isFalse);
            } else {
              expect(h.port.updates, isEmpty);
              expect(h.module.projection.value.settings, same(saved));
              expect(_switch(t, _realtimeKey).value, isTrue);
            }
            expect(h.port.reads, 1);
            expect(t.takeException(), isNull);
          } finally {
            if (!pending.isCompleted) {
              pending.complete(
                const SyncPrivacyWriteResult.failed(
                  SyncPrivacyFailure.writeFailed,
                ),
              );
            }
            await _frames(t, count: 2);
            await h.close(t);
          }
        },
        timeout: _timeout,
      );
    }

    testWidgets(
      '$suite draft scope accumulates choices without writes until explicit transaction save',
      (t) async {
        final h = await _Harness.create(t, suite, drafted: true);
        final pending = Completer<SyncPrivacyWriteResult>();
        try {
          await _toggle(t, _shipKey);
          await _frames(t, count: 2);
          await _toggle(t, const Key('privacy-friends-location'));
          await _frames(t, count: 2);
          await _toggle(t, _realtimeKey);
          await _frames(t);
          await t.tap(find.byKey(const Key('sync-privacy-pause-confirm')));
          await _frames(t);
          expect(h.port.updates, isEmpty);
          expect(h.drafts!.dirty, isTrue);
          expect(
            h.module.projection.value.settings!.friendDefaults.ship,
            isFalse,
          );
          expect(
            h.module.projection.value.settings!.realtimeSyncEnabled,
            isTrue,
          );
          expect(_switch(t, _shipKey).value, isTrue);
          expect(_switch(t, _realtimeKey).value, isFalse);
          h.port.pendingWrite = pending;
          final save = h.drafts!.save();
          await _frames(t, count: 2);
          expect(h.port.updates, hasLength(1));
          final submitted = h.port.updates.single;
          expect(submitted.$2, 7);
          expect(submitted.$1.friendDefaults.ship, isTrue);
          expect(submitted.$1.friendDefaults.location, isTrue);
          expect(submitted.$1.realtimeSyncEnabled, isFalse);
          expect(_switch(t, _shipKey).onChanged, isNull);
          pending.complete(SyncPrivacyWriteResult.completed(_receipt(h.port)));
          expect(await save, isTrue);
          await _frames(t);
          expect(h.drafts!.dirty, isFalse);
          expect(h.module.projection.value.revision, 8);
          expect(h.port.updates, hasLength(1));
          expect(t.takeException(), isNull);
        } finally {
          if (!pending.isCompleted) {
            pending.complete(
              const SyncPrivacyWriteResult.failed(
                SyncPrivacyFailure.writeFailed,
              ),
            );
          }
          await _frames(t, count: 2);
          await h.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite rejected unified draft remains editable and retries only on explicit save',
      (t) async {
        final h = await _Harness.create(t, suite, drafted: true);
        try {
          await _toggle(t, _shipKey);
          await _frames(t, count: 2);
          h.port.writeFailure = SyncPrivacyFailure.writeFailed;
          expect(await h.drafts!.save(), isFalse);
          await _frames(t);
          expect(h.drafts!.dirty, isTrue);
          expect(h.drafts!.failed, isTrue);
          expect(h.port.updates, hasLength(1));
          expect(h.port.reads, 1);
          expect(
            h.module.projection.value.settings!.friendDefaults.ship,
            isFalse,
          );
          expect(_switch(t, _shipKey).value, isTrue);
          h.port.writeFailure = null;
          expect(await h.drafts!.save(), isTrue);
          await _frames(t);
          expect(h.port.updates, hasLength(2));
          expect(h.port.updates.map((e) => e.$2), [7, 7]);
          expect(
            h.module.projection.value.settings!.friendDefaults.ship,
            isTrue,
          );
          expect(h.drafts!.dirty, isFalse);
          expect(h.drafts!.failed, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          await h.close(t);
        }
      },
      timeout: _timeout,
    );

    for (final failure in ['refused', 'throw', 'conflict']) {
      testWidgets(
        '$suite $failure retains confirmed values and original unknown read recovery',
        (t) async {
          final h = await _Harness.create(t, suite);
          final read = Completer<SyncPrivacySnapshot>();
          try {
            final confirmed = h.module.projection.value.settings!;
            if (failure == 'throw') {
              h.port.writeError = StateError('synthetic lost write response');
            } else {
              h.port.writeFailure = failure == 'refused'
                  ? SyncPrivacyFailure.writeFailed
                  : SyncPrivacyFailure.writeConflict;
            }
            if (failure != 'refused') h.port.pendingRead = read;
            await _toggle(t, _shipKey);
            await _frames(t, count: 2);
            expect(h.port.updates, hasLength(1));
            expect(h.module.projection.value.settings, same(confirmed));
            expect(_switch(t, _shipKey).value, isFalse);
            expect(h.port.reads, failure == 'refused' ? 1 : 2);
            if (failure == 'refused') {
              expect(h.module.projection.value.canEdit, isTrue);
              expect(
                h.module.projection.value.failure,
                SyncPrivacyFailure.writeFailed,
              );
            } else {
              expect(h.module.projection.value.canEdit, isFalse);
              expect(
                h.module.projection.value.operation,
                SyncPrivacyOperation.refreshing,
              );
              read.complete(
                const SyncPrivacySnapshot.unavailable(
                  failure: SyncPrivacyFailure.readFailed,
                ),
              );
              await _frames(t);
              expect(h.module.projection.value.settings, same(confirmed));
              expect(h.module.projection.value.canEdit, isFalse);
              expect(
                h.module.projection.value.failure,
                SyncPrivacyFailure.readFailed,
              );
              expect(_switch(t, _shipKey).onChanged, isNull);
            }
            h.port.writeError = null;
            h.port.writeFailure = null;
            h.port.pendingRead = null;
            await h.module.refresh();
            await _frames(t);
            expect(h.module.projection.value.canEdit, isTrue);
            expect(
              h.module.projection.value.settings!.friendDefaults.ship,
              isFalse,
            );
            expect(h.port.updates, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            if (!read.isCompleted) {
              read.complete(const SyncPrivacySnapshot.unavailable());
            }
            await _frames(t, count: 2);
            await h.close(t);
          }
        },
        timeout: _timeout,
      );
    }

    testWidgets(
      '$suite pending mutation guards old callback and serializes queued reads without replay',
      (t) async {
        final h = await _Harness.create(t, suite);
        final pending = Completer<SyncPrivacyWriteResult>();
        try {
          h.port.pendingWrite = pending;
          final oldCallback = _switch(t, _shipKey).onChanged!;
          await _toggle(t, _shipKey);
          await _frames(t, count: 2);
          expect(h.port.updates, hasLength(1));
          expect(_switch(t, _shipKey).onChanged, isNull);
          oldCallback(true);
          await h.module.refresh();
          await h.module.refresh();
          await _frames(t, count: 2);
          expect(h.port.updates, hasLength(1));
          expect(h.port.reads, 1);
          final receipt = _receipt(h.port);
          h.port.nextRead = receipt;
          pending.complete(SyncPrivacyWriteResult.completed(receipt));
          await _frames(t);
          expect(h.port.updates, hasLength(1));
          expect(h.port.reads, 2);
          expect(h.module.projection.value.revision, 8);
          expect(_switch(t, _shipKey).value, isTrue);
          expect(t.takeException(), isNull);
        } finally {
          if (!pending.isCompleted) {
            pending.complete(
              const SyncPrivacyWriteResult.failed(
                SyncPrivacyFailure.writeFailed,
              ),
            );
          }
          await _frames(t, count: 2);
          await h.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite account invalidation rejects late mutation receipt from old scope',
      (t) async {
        final h = await _Harness.create(t, suite);
        final pending = Completer<SyncPrivacyWriteResult>();
        try {
          h.port.pendingWrite = pending;
          await _toggle(t, _shipKey);
          await _frames(t, count: 2);
          final oldReceipt = _receipt(h.port);
          final replacement = h.port.inner.current.settings!.copyWith(
            friendDefaults: h.port.inner.current.settings!.friendDefaults
                .copyWith(location: true),
          );
          h.port.nextRead = SyncPrivacySnapshot.available(
            revision: 41,
            settings: replacement,
          );
          h.port.events.add(null);
          await _frames(t);
          expect(h.module.projection.value.revision, 41);
          expect(h.module.projection.value.settings, same(replacement));
          pending.complete(SyncPrivacyWriteResult.completed(oldReceipt));
          await _frames(t);
          expect(h.module.projection.value.revision, 41);
          expect(h.module.projection.value.settings, same(replacement));
          expect(_switch(t, _shipKey).value, isFalse);
          expect(h.port.updates, hasLength(1));
          expect(h.port.reads, 2);
          expect(t.takeException(), isNull);
        } finally {
          if (!pending.isCompleted) {
            pending.complete(
              const SyncPrivacyWriteResult.failed(
                SyncPrivacyFailure.writeFailed,
              ),
            );
          }
          await _frames(t, count: 2);
          await h.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite unmount retires presentation only and preserves original owner receipt',
      (t) async {
        final h = await _Harness.create(t, suite);
        final pending = Completer<SyncPrivacyWriteResult>();
        try {
          h.port.pendingWrite = pending;
          await _toggle(t, _shipKey);
          await _frames(t, count: 2);
          final receipt = _receipt(h.port);
          await t.pumpWidget(const SizedBox.shrink());
          await _frames(t, count: 2);
          pending.complete(SyncPrivacyWriteResult.completed(receipt));
          await _frames(t);
          expect(h.module.projection.value.revision, 8);
          expect(
            h.module.projection.value.settings!.friendDefaults.ship,
            isTrue,
          );
          expect(h.port.updates, hasLength(1));
          expect(h.port.reads, 1);
          expect(t.takeException(), isNull);
        } finally {
          if (!pending.isCompleted) {
            pending.complete(
              const SyncPrivacyWriteResult.failed(
                SyncPrivacyFailure.writeFailed,
              ),
            );
          }
          await _frames(t, count: 2);
          await h.close(t);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite same page element replacing module never inherits old pending wait or values',
      (t) async {
        final h = await _Harness.create(t, suite);
        final newPort = _Port();
        final newModule = createSyncPrivacyModule(newPort);
        final pending = Completer<SyncPrivacyWriteResult>();
        try {
          await newModule.initialize();
          final element = t.element(find.byType(SyncPrivacyPage));
          h.port.pendingWrite = pending;
          await _toggle(t, _shipKey);
          await _frames(t, count: 2);
          expect(find.byType(HelpSupportWaiting), findsOneWidget);
          final receipt = _receipt(h.port);
          await t.pumpWidget(h.page(owner: newModule));
          await _frames(t, count: 2);
          expect(t.element(find.byType(SyncPrivacyPage)), same(element));
          expect(find.byType(HelpSupportWaiting), findsNothing);
          expect(_switch(t, _shipKey).value, isFalse);
          pending.complete(SyncPrivacyWriteResult.completed(receipt));
          await _frames(t);
          expect(newModule.projection.value.revision, 7);
          expect(_switch(t, _shipKey).value, isFalse);
          expect(newPort.updates, isEmpty);
          expect(newPort.reads, 1);
          expect(h.module.projection.value.revision, 8);
          expect(t.takeException(), isNull);
        } finally {
          if (!pending.isCompleted) {
            pending.complete(
              const SyncPrivacyWriteResult.failed(
                SyncPrivacyFailure.writeFailed,
              ),
            );
          }
          await _frames(t, count: 2);
          await h.close(t);
          newModule.dispose();
        }
      },
      timeout: _timeout,
    );
  }
}
