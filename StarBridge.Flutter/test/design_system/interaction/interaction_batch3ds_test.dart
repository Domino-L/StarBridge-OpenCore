import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/in_memory_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_models.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_page.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_port.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3do_test.dart'
    show act, exposedNodes, loadFonts, scopedApp, size;

const _timeout = Timeout(Duration(seconds: 45));
const _ship = Key('privacy-friends-ship');
const _realtime = Key('privacy-realtime-sync');

Future<void> _frames(WidgetTester t, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

InteractionSource _source(String source) => source == 'pointer'
    ? InteractionSource.pointer
    : InteractionSource.keyboard;

class _Port implements SyncPrivacyPort {
  final inner = InMemorySyncPrivacyAdapter.forReview();
  final events = StreamController<void>.broadcast();
  final writes = <(SyncPrivacySettingsValue, int)>[];
  final writeSources = <InteractionSource>[];
  final readSources = <InteractionSource>[];
  Completer<SyncPrivacySnapshot>? pendingRead;
  Completer<SyncPrivacyWriteResult>? pendingWrite;
  SyncPrivacyFailure? writeFailure;

  @override
  Stream<void> get invalidations => events.stream;

  @override
  Future<SyncPrivacySnapshot> read() {
    readSources.add(currentStarBridgeActivationSource);
    return pendingRead?.future ?? inner.read();
  }

  @override
  Future<SyncPrivacyWriteResult> update(
    SyncPrivacySettingsValue settings, {
    required int expectedRevision,
  }) {
    writes.add((settings, expectedRevision));
    writeSources.add(currentStarBridgeActivationSource);
    if (writeFailure case final failure?) {
      return Future.value(SyncPrivacyWriteResult.failed(failure));
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
  _Harness(this.port, this.module, this.suite, this.initializing);
  final _Port port;
  final SyncPrivacyModule module;
  final InteractionSuite suite;
  final Future<void> initializing;

  Widget page({
    bool reduce = false,
    bool light = false,
    InteractionSource opening = InteractionSource.programmatic,
  }) {
    const key = Key('3ds-sync-owner-page');
    final page = SyncPrivacyPage(key: key, module: module);
    return scopedApp(
      opening == InteractionSource.programmatic
          ? page
          : Builder(
              builder: (context) => starBridgeInitialReadViewport(
                context,
                source: opening,
                child: page,
              ),
            ),
      suite,
      reduce: reduce,
      light: light,
    );
  }

  static Future<_Harness> create(
    WidgetTester t,
    InteractionSuite suite, {
    Completer<SyncPrivacySnapshot>? firstRead,
    InteractionSource opening = InteractionSource.programmatic,
  }) async {
    size(t, const Size(1280, 1100));
    final port = _Port()..pendingRead = firstRead;
    final module = createSyncPrivacyModule(port);
    final initializing = module.initialize();
    if (firstRead == null) await initializing;
    final h = _Harness(port, module, suite, initializing);
    await t.pumpWidget(h.page(opening: opening));
    await _frames(t, count: firstRead == null ? 10 : 2);
    expect(port.readSources, hasLength(1));
    expect(port.writes, isEmpty);
    return h;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await _frames(t, count: 2);
    module.dispose();
  }
}

StarBridgeSwitch _switch(WidgetTester t, Key key) => t.widget<StarBridgeSwitch>(
  find
      .ancestor(of: find.byKey(key), matching: find.byType(StarBridgeSwitch))
      .first,
);

Future<void> _toggle(
  WidgetTester t,
  Key key,
  String source,
  String label,
) async {
  final target = find.byKey(key);
  await t.ensureVisible(target);
  await t.pump();
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'keyboard') {
    final control = t.widget(target);
    final focus = switch (control) {
      Switch native => native.focusNode!,
      SuiteSwitch styled => styled.focusNode!,
      _ => throw StateError('Expected native or suite switch at $key'),
    };
    focus.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
  } else {
    final nodes = exposedNodes(t)
        .where(
          (node) =>
              node.getSemanticsData().label == label &&
              node.getSemanticsData().hasAction(SemanticsAction.tap),
        )
        .toList();
    expect(nodes, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      SemanticsAction.tap,
    );
  }
  await t.pump();
}

void _waiting(WidgetTester t, InteractionSource source, {bool reduce = false}) {
  final waiting = find.byType(HelpSupportWaiting);
  expect(waiting, findsOneWidget);
  expect(t.widget<HelpSupportWaiting>(waiting).source, source);
  expect(
    find.byType(SuiteProgressBar),
    reduce || source == InteractionSource.keyboard
        ? findsNothing
        : findsOneWidget,
  );
}

SyncPrivacyWriteResult _receipt(_Port port) => SyncPrivacyWriteResult.completed(
  SyncPrivacySnapshot.available(revision: 8, settings: port.writes.last.$1),
);

Future<void> _releaseWrite(
  WidgetTester t,
  Completer<SyncPrivacyWriteResult> pending,
) async {
  if (!pending.isCompleted) {
    pending.complete(
      const SyncPrivacyWriteResult.failed(SyncPrivacyFailure.writeFailed),
    );
  }
  await _frames(t, count: 2);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source switch preserves confirmed owner values until actual write acknowledgement',
        (t) async {
          final semantics = t.ensureSemantics();
          final h = await _Harness.create(t, suite);
          final pending = Completer<SyncPrivacyWriteResult>();
          try {
            final confirmed = h.module.projection.value.settings!;
            expect(confirmed.friendDefaults.ship, isFalse);
            h.port.pendingWrite = pending;
            await _toggle(t, _ship, source, '当前舰船');
            await _frames(t, count: 2);
            expect(h.port.writes, hasLength(1));
            expect(h.port.writes.single.$2, 7);
            expect(h.port.writeSources, [_source(source)]);
            final submitted = h.port.writes.single.$1;
            expect(submitted.friendDefaults.ship, isTrue);
            expect(
              submitted.realtimeSyncEnabled,
              confirmed.realtimeSyncEnabled,
            );
            expect(submitted.eventSharing, same(confirmed.eventSharing));
            expect(submitted.social, same(confirmed.social));
            expect(h.module.projection.value.settings, same(confirmed));
            expect(
              h.module.projection.value.operation,
              SyncPrivacyOperation.saving,
            );
            expect(_switch(t, _ship).value, isFalse);
            expect(_switch(t, _ship).onChanged, isNull);
            _waiting(t, _source(source));
            final phase = t.widget(find.byType(HelpSupportWaiting)).key;
            await _frames(t, count: 3);
            expect(t.widget(find.byType(HelpSupportWaiting)).key, phase);
            expect(h.port.writes, hasLength(1));
            pending.complete(_receipt(h.port));
            await _frames(t);
            expect(_switch(t, _ship).value, isTrue);
            expect(_switch(t, _ship).onChanged, isNotNull);
            expect(h.module.projection.value.revision, 8);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(h.port.readSources, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            await _releaseWrite(t, pending);
            await h.close(t);
            semantics.dispose();
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $source explicit failure retry owns its wait source and never replays mutation',
        (t) async {
          final semantics = t.ensureSemantics();
          final h = await _Harness.create(t, suite);
          final pendingRead = Completer<SyncPrivacySnapshot>();
          try {
            final confirmed = h.module.projection.value.settings!;
            h.port.writeFailure = SyncPrivacyFailure.writeFailed;
            await _toggle(t, _ship, 'pointer', '当前舰船');
            await _frames(t);
            expect(
              h.module.projection.value.failure,
              SyncPrivacyFailure.writeFailed,
            );
            expect(h.module.projection.value.settings, same(confirmed));
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(h.port.writes, hasLength(1));
            h.port.pendingRead = pendingRead;
            await act(
              t,
              find.byKey(const Key('sync-privacy-retry')),
              source,
              '重新读取',
            );
            await _frames(t, count: 2);
            expect(h.port.readSources, hasLength(2));
            expect(h.port.readSources.last, _source(source));
            expect(h.port.writes, hasLength(1));
            expect(h.module.projection.value.settings, same(confirmed));
            expect(
              h.module.projection.value.operation,
              SyncPrivacyOperation.refreshing,
            );
            _waiting(t, _source(source));
            pendingRead.complete(h.port.inner.current);
            await _frames(t);
            expect(h.module.projection.value.revision, 7);
            expect(h.module.projection.value.failure, isNull);
            expect(h.module.projection.value.canEdit, isTrue);
            expect(_switch(t, _ship).value, isFalse);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(h.port.writes, hasLength(1));
            expect(h.port.readSources, hasLength(2));
            expect(t.takeException(), isNull);
          } finally {
            if (!pendingRead.isCompleted) {
              pendingRead.complete(const SyncPrivacySnapshot.unavailable());
            }
            await _frames(t, count: 2);
            await h.close(t);
            semantics.dispose();
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $source unavailable read retry owns loading origin without granting edit authority',
        (t) async {
          final semantics = t.ensureSemantics();
          final first = Completer<SyncPrivacySnapshot>();
          final h = await _Harness.create(t, suite, firstRead: first);
          final retry = Completer<SyncPrivacySnapshot>();
          try {
            first.complete(
              const SyncPrivacySnapshot.unavailable(
                failure: SyncPrivacyFailure.readFailed,
              ),
            );
            await h.initializing;
            await _frames(t);
            expect(
              h.module.projection.value.availability,
              SyncPrivacyAvailability.unavailable,
            );
            expect(h.module.projection.value.canEdit, isFalse);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            h.port.pendingRead = retry;
            await act(
              t,
              find.byKey(const Key('sync-privacy-retry')),
              source,
              '重新读取',
            );
            await _frames(t, count: 2);
            expect(h.port.readSources, hasLength(2));
            expect(h.port.readSources.last, _source(source));
            expect(
              h.module.projection.value.availability,
              SyncPrivacyAvailability.loading,
            );
            expect(h.module.projection.value.canEdit, isFalse);
            expect(find.byType(StarBridgeSwitch), findsNothing);
            _waiting(t, _source(source));
            expect(h.port.writes, isEmpty);
            retry.complete(h.port.inner.current);
            await _frames(t);
            expect(h.module.projection.value.canEdit, isTrue);
            expect(h.module.projection.value.revision, 7);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(h.port.writes, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            if (!first.isCompleted) {
              first.complete(const SyncPrivacySnapshot.unavailable());
            }
            if (!retry.isCompleted) {
              retry.complete(const SyncPrivacySnapshot.unavailable());
            }
            await _frames(t, count: 2);
            await h.close(t);
            semantics.dispose();
          }
        },
        timeout: _timeout,
      );
    }

    for (final confirmation in ['keyboard', 'reader']) {
      testWidgets(
        '$suite pointer opens pause but $confirmation confirmation owns final mutation source',
        (t) async {
          final semantics = t.ensureSemantics();
          final h = await _Harness.create(t, suite);
          final pending = Completer<SyncPrivacyWriteResult>();
          try {
            final confirmed = h.module.projection.value.settings!;
            await _toggle(t, _realtime, 'pointer', '启用实时同步');
            await _frames(t);
            final dialog = find.byType(AlertDialog);
            final route =
                ModalRoute.of(t.element(dialog)) as StarBridgeDialogRoute<bool>;
            expect(route.instant, isFalse);
            expect(h.port.writes, isEmpty);
            expect(h.module.projection.value.settings, same(confirmed));
            expect(find.byType(HelpSupportWaiting), findsNothing);
            h.port.pendingWrite = pending;
            await act(
              t,
              find.byKey(const Key('sync-privacy-pause-confirm')),
              confirmation,
              '暂停实时同步',
            );
            await _frames(t, count: 2);
            expect(dialog, findsNothing);
            expect(h.port.writes, hasLength(1));
            expect(h.port.writeSources, [InteractionSource.keyboard]);
            expect(h.port.writes.single.$1.realtimeSyncEnabled, isFalse);
            expect(h.port.writes.single.$2, 7);
            expect(
              h.port.writes.single.$1.friendDefaults,
              same(confirmed.friendDefaults),
            );
            expect(h.module.projection.value.settings, same(confirmed));
            expect(_switch(t, _realtime).value, isTrue);
            _waiting(t, InteractionSource.keyboard);
            pending.complete(_receipt(h.port));
            await _frames(t);
            expect(_switch(t, _realtime).value, isFalse);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(h.port.writes, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            await _releaseWrite(t, pending);
            await h.close(t);
            semantics.dispose();
          }
        },
        timeout: _timeout,
      );
    }

    testWidgets(
      '$suite live reduced motion stops only wait decoration without cancelling owner operation',
      (t) async {
        final h = await _Harness.create(t, suite);
        final pending = Completer<SyncPrivacyWriteResult>();
        try {
          h.port.pendingWrite = pending;
          await _toggle(t, _ship, 'pointer', '当前舰船');
          await _frames(t, count: 2);
          _waiting(t, InteractionSource.pointer);
          final element = t.element(find.byType(SyncPrivacyPage));
          final phase = t.widget(find.byType(HelpSupportWaiting)).key;
          await t.pumpWidget(h.page(reduce: true, light: true));
          await t.pump(const Duration(milliseconds: 16));
          expect(t.element(find.byType(SyncPrivacyPage)), same(element));
          expect(t.widget(find.byType(HelpSupportWaiting)).key, phase);
          _waiting(t, InteractionSource.pointer, reduce: true);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.text('正在保存…'), findsOneWidget);
          await _frames(t, count: 4);
          expect(h.port.writes, hasLength(1));
          expect(
            h.module.projection.value.operation,
            SyncPrivacyOperation.saving,
          );
          expect(_switch(t, _ship).value, isFalse);
          _waiting(t, InteractionSource.pointer, reduce: true);
          pending.complete(_receipt(h.port));
          await _frames(t);
          expect(_switch(t, _ship).value, isTrue);
          expect(find.byType(HelpSupportWaiting), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await _releaseWrite(t, pending);
          await h.close(t);
        }
      },
      timeout: _timeout,
    );

    for (final opening in [
      InteractionSource.programmatic,
      InteractionSource.keyboard,
    ]) {
      testWidgets(
        '$suite $opening initial loading has no optimistic controls and retains initial read origin',
        (t) async {
          final pending = Completer<SyncPrivacySnapshot>();
          final h = await _Harness.create(
            t,
            suite,
            firstRead: pending,
            opening: opening,
          );
          try {
            expect(
              h.module.projection.value.availability,
              SyncPrivacyAvailability.loading,
            );
            expect(find.byType(StarBridgeSwitch), findsNothing);
            expect(find.text('正在读取同步与隐私设置…'), findsOneWidget);
            final wait = t.widget<HelpSupportWaiting>(
              find.byType(HelpSupportWaiting),
            );
            expect(wait.source, InteractionSource.programmatic);
            expect(
              find.byType(SuiteProgressBar),
              opening == InteractionSource.keyboard
                  ? findsNothing
                  : findsOneWidget,
            );
            await _frames(t, count: 3);
            expect(h.port.readSources, hasLength(1));
            expect(h.port.writes, isEmpty);
            pending.complete(h.port.inner.current);
            await h.initializing;
            await _frames(t);
            expect(h.module.projection.value.revision, 7);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(_switch(t, _ship).value, isFalse);
            expect(h.port.writes, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            if (!pending.isCompleted) {
              pending.complete(const SyncPrivacySnapshot.unavailable());
            }
            await _frames(t, count: 2);
            await h.close(t);
          }
        },
        timeout: _timeout,
      );
    }
  }
}
