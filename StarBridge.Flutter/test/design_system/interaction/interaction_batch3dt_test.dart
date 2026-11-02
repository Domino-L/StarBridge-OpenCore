import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/direct_message_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/direct_message_privacy_setting.dart';
import 'package:starbridge_flutter/features/settings/friend_request_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/friend_request_privacy_setting.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/help_support_action.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/features/settings/recently_played_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/recently_played_privacy_setting.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3do_test.dart'
    show act, exposedNodes, loadFonts, scopedApp, size;

const _timeout = Timeout(Duration(seconds: 45));

Future<void> _frames(WidgetTester t, {int count = 4}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

class _Gate {
  final writes = <bool>[];
  final revisions = <int?>[];
  final writeSources = <InteractionSource>[];
  final readSources = <InteractionSource>[];
  Completer<void>? readGate;
  Completer<void>? writeGate;
  bool unavailable = false;
  bool rejected = false;
  bool saved = false;
  int revision = 7;

  Future<void> read() async {
    readSources.add(currentStarBridgeActivationSource);
    await readGate?.future;
  }

  Future<void> write(bool next, {int? expectedRevision}) async {
    writes.add(next);
    revisions.add(expectedRevision);
    writeSources.add(currentStarBridgeActivationSource);
    await writeGate?.future;
    if (!rejected) {
      saved = next;
      revision++;
    }
  }

  void release() {
    final read = readGate;
    final write = writeGate;
    if (read != null && !read.isCompleted) read.complete();
    if (write != null && !write.isCompleted) write.complete();
  }
}

class _DirectPort implements DirectMessagePrivacyPort {
  _DirectPort(this.gate);
  final _Gate gate;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<DirectMessagePrivacySnapshot> read() async {
    await gate.read();
    return gate.unavailable
        ? const DirectMessagePrivacySnapshot.unavailable(
            DirectMessagePrivacyFailure.readFailed,
          )
        : DirectMessagePrivacySnapshot.available(
            allowStrangerDirectMessages: gate.saved,
            updatedAt: null,
          );
  }

  @override
  Future<DirectMessagePrivacyWriteResult> save(bool next) async {
    await gate.write(next);
    return gate.rejected
        ? const DirectMessagePrivacyWriteResult.rejected(
            DirectMessagePrivacyFailure.writeFailed,
          )
        : DirectMessagePrivacyWriteResult.completed(
            DirectMessagePrivacySnapshot.available(
              allowStrangerDirectMessages: next,
              updatedAt: null,
            ),
          );
  }

  @override
  Future<void> close() async {}
}

class _FriendPort implements FriendRequestPrivacyPort {
  _FriendPort(this.gate);
  final _Gate gate;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<FriendRequestPrivacySnapshot> read() async {
    await gate.read();
    return gate.unavailable
        ? const FriendRequestPrivacySnapshot.unavailable(
            FriendRequestPrivacyFailure.readFailed,
          )
        : FriendRequestPrivacySnapshot.available(
            allowFriendRequests: gate.saved,
            updatedAt: null,
          );
  }

  @override
  Future<FriendRequestPrivacyWriteResult> save(bool next) async {
    await gate.write(next);
    return gate.rejected
        ? const FriendRequestPrivacyWriteResult.rejected(
            FriendRequestPrivacyFailure.writeFailed,
          )
        : FriendRequestPrivacyWriteResult.completed(
            FriendRequestPrivacySnapshot.available(
              allowFriendRequests: next,
              updatedAt: null,
            ),
          );
  }

  @override
  Future<void> close() async {}
}

class _RecentPort implements RecentlyPlayedPrivacyPort {
  _RecentPort(this.gate);
  final _Gate gate;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<RecentlyPlayedPrivacySnapshot> read() async {
    await gate.read();
    return gate.unavailable
        ? const RecentlyPlayedPrivacySnapshot.unavailable(
            RecentlyPlayedPrivacyFailure.readFailed,
          )
        : RecentlyPlayedPrivacySnapshot.available(
            enabled: gate.saved,
            enabledAt: null,
            disabledAt: null,
            revision: gate.revision,
          );
  }

  @override
  Future<RecentlyPlayedPrivacyWriteResult> save(bool next, int revision) async {
    await gate.write(next, expectedRevision: revision);
    return gate.rejected
        ? const RecentlyPlayedPrivacyWriteResult.rejected(
            RecentlyPlayedPrivacyFailure.writeFailed,
          )
        : RecentlyPlayedPrivacyWriteResult.completed(
            RecentlyPlayedPrivacySnapshot.available(
              enabled: next,
              enabledAt: null,
              disabledAt: null,
              revision: revision + 1,
            ),
          );
  }

  @override
  Future<void> close() async {}
}

class _Owner {
  _Owner(
    this.kind,
    this.gate,
    this.setting,
    this.initialize,
    this.dispose,
    this.value,
    this.canEdit,
  );
  final String kind;
  final _Gate gate;
  final Widget setting;
  final Future<void> Function() initialize;
  final VoidCallback dispose;
  final ValueGetter<bool?> value;
  final ValueGetter<bool> canEdit;

  Key get control => Key(switch (kind) {
    'direct' => 'privacy-stranger-messages-authoritative',
    'friend' => 'privacy-friend-requests-authoritative',
    _ => 'privacy-recently-played-authoritative',
  });
  String get label => switch (kind) {
    'direct' => '允许非好友发起私信',
    'friend' => '允许非好友发送好友申请',
    _ => '允许共同参与者在“最近同玩”中找到我',
  };

  static _Owner create(String kind) {
    final gate = _Gate();
    switch (kind) {
      case 'direct':
        final module = DirectMessagePrivacyModule(_DirectPort(gate));
        return _Owner(
          kind,
          gate,
          DirectMessagePrivacySetting(module: module),
          module.initialize,
          module.dispose,
          () => module.projection.value.snapshot.allowStrangerDirectMessages,
          () => module.projection.value.canEdit,
        );
      case 'friend':
        final module = FriendRequestPrivacyModule(_FriendPort(gate));
        return _Owner(
          kind,
          gate,
          FriendRequestPrivacySetting(module: module),
          module.initialize,
          module.dispose,
          () => module.projection.value.snapshot.allowFriendRequests,
          () => module.projection.value.canEdit,
        );
      default:
        final module = RecentlyPlayedPrivacyModule(_RecentPort(gate));
        return _Owner(
          kind,
          gate,
          RecentlyPlayedPrivacySetting(module: module),
          module.initialize,
          module.dispose,
          () => module.projection.value.snapshot.enabled,
          () => module.projection.value.canEdit,
        );
    }
  }
}

Widget _app(
  _Owner owner,
  InteractionSuite suite, {
  bool reduce = false,
  bool keyboardOpening = false,
  PrivacyPageDrafts? drafts,
}) {
  Widget body = Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      owner.setting,
      if (drafts != null)
        HelpSupportAction(
          controlKey: const Key('3dt-draft-save'),
          onActivate: (source) =>
              runStarBridgeActivation<void>(source, () async {
                await drafts.save();
              }),
          child: const Text('保存草稿'),
        ),
    ],
  );
  if (drafts != null) body = PrivacyDraftScope(drafts: drafts, child: body);
  final content = Padding(padding: const EdgeInsets.all(24), child: body);
  return scopedApp(
    keyboardOpening
        ? Builder(
            builder: (context) => starBridgeInitialReadViewport(
              context,
              source: InteractionSource.keyboard,
              child: content,
            ),
          )
        : content,
    suite,
    reduce: reduce,
  );
}

StarBridgeSwitch _switch(WidgetTester t, _Owner owner) =>
    t.widget<StarBridgeSwitch>(
      find
          .ancestor(
            of: find.byKey(owner.control),
            matching: find.byType(StarBridgeSwitch),
          )
          .first,
    );

Future<void> _toggle(WidgetTester t, _Owner owner, String source) async {
  final target = find.byKey(owner.control);
  await t.ensureVisible(target);
  await t.pump();
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'keyboard') {
    final control = t.widget(target);
    final focus = switch (control) {
      Switch value => value.focusNode!,
      SuiteSwitch value => value.focusNode!,
      _ => throw StateError('Missing switch at ${owner.control}'),
    };
    focus.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
  } else {
    final nodes = exposedNodes(t)
        .where(
          (node) =>
              node.getSemanticsData().label == owner.label &&
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
  expect(find.byType(HelpSupportWaiting), findsOneWidget);
  expect(
    t.widget<HelpSupportWaiting>(find.byType(HelpSupportWaiting)).source,
    source,
  );
  expect(find.byType(LinearProgressIndicator), findsNothing);
  expect(
    find.byType(SuiteProgressBar),
    reduce || source == InteractionSource.keyboard
        ? findsNothing
        : findsOneWidget,
  );
}

Future<void> _close(WidgetTester t, _Owner owner) async {
  owner.gate.release();
  await _frames(t, count: 2);
  await t.pumpWidget(const SizedBox.shrink());
  owner.dispose();
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final kind in ['direct', 'friend', 'recent']) {
      testWidgets(
        '$suite $kind first read uses approved waiting rather than a raw indicator',
        (t) async {
          size(t, const Size(1000, 800));
          final owner = _Owner.create(kind);
          try {
            await t.pumpWidget(scopedApp(owner.setting, suite));
            await _frames(t, count: 2);
            expect(find.byType(HelpSupportWaiting), findsOneWidget);
            expect(find.byType(LinearProgressIndicator), findsNothing);
            await owner.initialize();
            await _frames(t);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox.shrink());
            owner.dispose();
          }
        },
        timeout: _timeout,
      );

      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '$suite $kind $source actual owner save freezes its own wait and retains confirmed value',
          (t) async {
            final semantics = t.ensureSemantics();
            final owner = _Owner.create(kind);
            try {
              size(t, const Size(1000, 800));
              await owner.initialize();
              await t.pumpWidget(_app(owner, suite));
              await _frames(t);
              final pending = Completer<void>();
              owner.gate.writeGate = pending;
              await _toggle(t, owner, source);
              await _frames(t, count: 2);
              final expected = source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard;
              expect(owner.gate.writes, [true]);
              expect(owner.gate.writeSources, [expected]);
              expect(owner.gate.revisions, [kind == 'recent' ? 7 : null]);
              expect(owner.value(), isFalse);
              expect(owner.canEdit(), isFalse);
              expect(_switch(t, owner).value, isFalse);
              expect(_switch(t, owner).onChanged, isNull);
              _waiting(t, expected);
              final phase = t.widget(find.byType(HelpSupportWaiting)).key;
              await _frames(t, count: 3);
              expect(t.widget(find.byType(HelpSupportWaiting)).key, phase);
              expect(owner.gate.writes, hasLength(1));
              pending.complete();
              await _frames(t);
              expect(owner.value(), isTrue);
              expect(owner.canEdit(), isTrue);
              expect(_switch(t, owner).value, isTrue);
              expect(find.byType(HelpSupportWaiting), findsNothing);
              expect(owner.gate.readSources, hasLength(1));
              expect(t.takeException(), isNull);
            } finally {
              await _close(t, owner);
              semantics.dispose();
            }
          },
          timeout: _timeout,
        );
      }

      testWidgets(
        '$suite $kind pointer draft edit never labels a later keyboard transaction save',
        (t) async {
          final owner = _Owner.create(kind);
          final drafts = PrivacyPageDrafts();
          try {
            size(t, const Size(1000, 800));
            await owner.initialize();
            await t.pumpWidget(_app(owner, suite, drafts: drafts));
            await _frames(t);
            await _toggle(t, owner, 'pointer');
            await _frames(t, count: 2);
            expect(drafts.dirty, isTrue);
            expect(owner.gate.writes, isEmpty);
            expect(owner.value(), isFalse);
            expect(_switch(t, owner).value, isTrue);
            final pending = Completer<void>();
            owner.gate.writeGate = pending;
            await act(
              t,
              find.byKey(const Key('3dt-draft-save')),
              'keyboard',
              '保存草稿',
            );
            await _frames(t, count: 2);
            expect(owner.gate.writes, [true]);
            expect(owner.gate.writeSources, [InteractionSource.keyboard]);
            expect(owner.value(), isFalse);
            expect(drafts.saving, isTrue);
            _waiting(t, InteractionSource.keyboard);
            pending.complete();
            await _frames(t);
            expect(owner.value(), isTrue);
            expect(drafts.dirty, isFalse);
            expect(drafts.saving, isFalse);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await _close(t, owner);
            drafts.dispose();
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $kind keyboard initial viewport makes only first-read decoration static',
        (t) async {
          final owner = _Owner.create(kind);
          try {
            size(t, const Size(1000, 800));
            final read = Completer<void>();
            owner.gate.readGate = read;
            final initializing = owner.initialize();
            await t.pumpWidget(_app(owner, suite, keyboardOpening: true));
            await _frames(t, count: 2);
            expect(find.byType(HelpSupportWaiting), findsOneWidget);
            expect(find.byType(SuiteProgressBar), findsNothing);
            expect(find.byType(LinearProgressIndicator), findsNothing);
            expect(find.byType(StarBridgeSwitch), findsNothing);
            expect(owner.gate.writes, isEmpty);
            expect(owner.gate.readSources, hasLength(1));
            read.complete();
            await initializing;
            await _frames(t);
            expect(owner.value(), isFalse);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(_switch(t, owner).onChanged, isNotNull);
            expect(t.takeException(), isNull);
          } finally {
            await _close(t, owner);
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $kind live reduce retains request and phase but stops pending decoration',
        (t) async {
          final owner = _Owner.create(kind);
          try {
            size(t, const Size(1000, 800));
            await owner.initialize();
            await t.pumpWidget(_app(owner, suite));
            await _frames(t);
            final pending = Completer<void>();
            owner.gate.writeGate = pending;
            await _toggle(t, owner, 'pointer');
            await _frames(t, count: 2);
            _waiting(t, InteractionSource.pointer);
            final element = t.element(find.byType(HelpSupportWaiting));
            final phase = t.widget(find.byType(HelpSupportWaiting)).key;
            await t.pumpWidget(_app(owner, suite, reduce: true));
            await t.pump(const Duration(milliseconds: 16));
            expect(t.element(find.byType(HelpSupportWaiting)), same(element));
            expect(t.widget(find.byType(HelpSupportWaiting)).key, phase);
            _waiting(t, InteractionSource.pointer, reduce: true);
            expect(owner.gate.writes, hasLength(1));
            expect(owner.value(), isFalse);
            pending.complete();
            await _frames(t);
            expect(owner.value(), isTrue);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await _close(t, owner);
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $kind all retry sources decorate the actual future without replacing owner duplicate admission',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            size(t, const Size(1000, 800));
            for (final source in ['pointer', 'keyboard', 'reader']) {
              final owner = _Owner.create(kind);
              try {
                owner.gate.unavailable = true;
                await owner.initialize();
                await t.pumpWidget(_app(owner, suite));
                await _frames(t);
                expect(owner.value(), isNull);
                expect(owner.canEdit(), isFalse);
                final retry = find.widgetWithText(HelpSupportAction, '重新读取');
                expect(retry, findsOneWidget);
                final callback = t.widget<HelpSupportAction>(retry).onActivate!;
                final pending = Completer<void>();
                owner.gate.readGate = pending;
                await act(t, retry, source, '重新读取');
                await _frames(t, count: 2);
                final expected = source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard;
                _waiting(t, expected);
                final phase = t.widget(find.byType(HelpSupportWaiting)).key;
                expect(owner.gate.readSources, hasLength(2));
                expect(owner.gate.readSources.last, expected);
                expect(
                  t.widget<HelpSupportAction>(retry).onActivate,
                  isNotNull,
                );
                // The entry stays enabled. Original module._reading rejects
                // the duplicate; presentation must not add a business lock.
                callback(InteractionSource.pointer);
                await _frames(t, count: 2);
                expect(owner.gate.readSources, hasLength(2));
                expect(t.widget(find.byType(HelpSupportWaiting)).key, phase);
                expect(owner.gate.writes, isEmpty);
                expect(owner.value(), isNull);
                owner.gate.unavailable = false;
                pending.complete();
                await _frames(t);
                expect(owner.value(), isFalse);
                expect(owner.canEdit(), isTrue);
                expect(find.byType(HelpSupportWaiting), findsNothing);
                expect(
                  find.widgetWithText(HelpSupportAction, '重新读取'),
                  findsNothing,
                );
                expect(owner.gate.writes, isEmpty);
                expect(t.takeException(), isNull);
              } finally {
                await _close(t, owner);
              }
            }
          } finally {
            semantics.dispose();
          }
        },
        timeout: _timeout,
      );
    }
  }
}
