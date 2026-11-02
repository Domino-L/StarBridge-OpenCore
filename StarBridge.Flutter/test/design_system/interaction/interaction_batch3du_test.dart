import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/friend_sharing_controller.dart';
import 'package:starbridge_flutter/features/settings/friend_sharing_setting.dart';
import 'package:starbridge_flutter/features/settings/game_id_visibility_controller.dart';
import 'package:starbridge_flutter/features/settings/game_id_visibility_setting.dart';
import 'package:starbridge_flutter/features/settings/help_support_action.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3do_test.dart'
    show act, exposedNodes, loadFonts, scopedApp, size;

const _timeout = Timeout(Duration(seconds: 45));

Future<void> _frames(WidgetTester t, {int count = 4}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

class _Bridge {
  _Bridge(this.kind) {
    final pair = InMemoryBridgeConnection.createPair();
    host = pair.host;
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 4)
      ..acceptHostCapabilities([
        kind == 'friend'
            ? 'friendSharing.settings'
            : 'gameIdVisibility.settings',
      ]);
    subscription = host.incoming.listen((request) {
      requests.add(request);
      if (request.name == 'account.getCurrent') {
        unawaited(
          reply(request, const {'schemaVersion': 1, 'state': 'signedIn'}),
        );
      }
    });
  }
  final String kind;
  late final BridgeConnection host;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  static const account = BridgeAccountContext(
    environment: 'test',
    authority: 'scm',
    subject: '3du-synthetic',
  );

  Widget get setting => kind == 'friend'
      ? FriendSharingSetting(session: session)
      : GameIdVisibilitySetting(session: session);

  String get readName =>
      kind == 'friend' ? 'friendSharing.read' : 'gameIdVisibility.read';
  String get saveName =>
      kind == 'friend' ? 'friendSharing.save' : 'gameIdVisibility.save';
  List<BridgeEnvelope> get reads =>
      requests.where((r) => r.name == readName).toList();
  List<BridgeEnvelope> get saves =>
      requests.where((r) => r.name == saveName).toList();
  Key get control =>
      Key(kind == 'friend' ? 'friend-sharing-ship' : 'game-id-profile');
  String get label => kind == 'friend' ? '当前舰船' : '个人主页';

  Map<String, Object?> snapshot() => kind == 'friend'
      ? {
          'state': 'inactive',
          'snapshot': {
            'schemaVersion': 1,
            'revision': 7,
            'operationId': '0' * 32,
            'appliedAt': '2026-10-16T00:00:00Z',
            'fields': 0,
          },
        }
      : {
          'schemaVersion': 1,
          'revision': 7,
          'locations': 0,
          'canConfigure': true,
          'identityStamp': 'a' * 64,
        };

  Future<void> reply(BridgeEnvelope request, Map<String, Object?> payload) =>
      host.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: account,
          status: 'ok',
          payload: payload,
        ),
      );

  Future<void> acknowledgeSave(int index) {
    final request = saves[index];
    final revision = (request.payload['expectedRevision'] as int) + 1;
    return reply(
      request,
      kind == 'friend'
          ? {
              'state': 'inactive',
              'snapshot': {
                'schemaVersion': 1,
                'revision': revision,
                'operationId': request.payload['operationId'],
                'appliedAt': '2026-10-16T00:00:00Z',
                'fields': request.payload['fields'],
              },
            }
          : {
              'schemaVersion': 1,
              'revision': revision,
              'locations': request.payload['locations'],
              'canConfigure': true,
              'identityStamp': 'a' * 64,
            },
    );
  }

  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await host.close();
  }
}

Widget _app(
  _Bridge bridge,
  InteractionSuite suite, {
  PrivacyPageDrafts? drafts,
  bool reduce = false,
  bool keyboardOpening = false,
}) {
  Widget body = Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      bridge.setting,
      if (drafts != null)
        HelpSupportAction(
          controlKey: const Key('3du-draft-save'),
          onActivate: (source) =>
              runStarBridgeActivation<void>(source, () async {
                await drafts.save();
              }),
          child: const Text('保存草稿'),
        ),
    ],
  );
  if (drafts != null) body = PrivacyDraftScope(drafts: drafts, child: body);
  final content = SingleChildScrollView(child: body);
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

class _Access {
  _Access(
    this.mask,
    this.snapshot,
    this.busy,
    this.canEdit,
    this.save,
    this.refresh,
  );
  final ValueGetter<int> mask;
  final ValueGetter<Map<String, Object?>?> snapshot;
  final ValueGetter<bool> busy;
  final ValueGetter<bool> canEdit;
  final Future<void> Function(int) save;
  final Future<void> Function() refresh;
  static _Access of(WidgetTester t, _Bridge bridge) {
    // Read the controller already owned by the real Setting; never instantiate
    // a second controller, subscription, first read or periodic timer.
    if (bridge.kind == 'friend') {
      final dynamic state = t.state(find.byType(FriendSharingSetting));
      final controller = state.controller as FriendSharingController;
      return _Access(
        () => controller.fields,
        () => controller.snapshot,
        () => controller.busy,
        () => controller.canEdit,
        controller.saveFields,
        controller.refresh,
      );
    }
    final dynamic state = t.state(find.byType(GameIdVisibilitySetting));
    final controller = state.controller as GameIdVisibilityController;
    return _Access(
      () => controller.locations,
      () => controller.snapshot,
      () => controller.busy,
      () => controller.canEdit,
      controller.saveLocations,
      controller.refresh,
    );
  }
}

StarBridgeSwitch _switch(WidgetTester t, _Bridge bridge) =>
    t.widget<StarBridgeSwitch>(
      find
          .ancestor(
            of: find.byKey(bridge.control),
            matching: find.byType(StarBridgeSwitch),
          )
          .first,
    );

Future<void> _toggle(WidgetTester t, _Bridge bridge, String source) async {
  final inner = find.byKey(bridge.control);
  await t.ensureVisible(inner);
  await t.pump();
  final outer = find
      .ancestor(of: inner, matching: find.byType(StarBridgeSwitch))
      .first;
  final row = find.descendant(of: outer, matching: find.byType(SuitePressable));
  expect(row, findsOneWidget);
  if (source == 'pointer') {
    await t.tap(row);
  } else if (source == 'keyboard') {
    t.widget<SuitePressable>(row).focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final nodes = exposedNodes(t)
        .where(
          (node) =>
              node.getSemanticsData().label == bridge.label &&
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

Future<_Access> _ready(
  WidgetTester t,
  _Bridge bridge,
  InteractionSuite suite, {
  PrivacyPageDrafts? drafts,
}) async {
  size(t, const Size(1000, 900));
  await t.pumpWidget(_app(bridge, suite, drafts: drafts));
  await _frames(t, count: 2);
  expect(bridge.reads, hasLength(1));
  await bridge.reply(bridge.reads.single, bridge.snapshot());
  await _frames(t);
  final access = _Access.of(t, bridge);
  expect(access.canEdit(), isTrue);
  expect(access.mask(), 0);
  return access;
}

Future<void> _close(WidgetTester t, _Bridge bridge) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.runAsync(bridge.close);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final kind in ['friend', 'game']) {
      testWidgets(
        '$suite $kind actual setting initial read uses approved waiting and no raw progress',
        (t) async {
          size(t, const Size(1000, 900));
          final bridge = _Bridge(kind);
          try {
            await t.pumpWidget(_app(bridge, suite));
            await _frames(t, count: 2);
            expect(
              bridge.requests.where((r) => r.name == bridge.readName),
              hasLength(1),
            );
            expect(find.byType(HelpSupportWaiting), findsOneWidget);
            expect(find.byType(LinearProgressIndicator), findsNothing);
            await bridge.reply(
              bridge.requests.singleWhere((r) => r.name == bridge.readName),
              bridge.snapshot(),
            );
            await _frames(t);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox.shrink());
            await t.runAsync(bridge.close);
          }
        },
        timeout: _timeout,
      );

      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '$suite $kind $source tile retains confirmed mask and decorates the actual pending save',
          (t) async {
            final semantics = t.ensureSemantics();
            final bridge = _Bridge(kind);
            try {
              final access = await _ready(t, bridge, suite);
              final before = access.snapshot();
              await _toggle(t, bridge, source);
              await _frames(t, count: 2);
              final expected = source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard;
              _waiting(t, expected);
              expect(access.busy(), isTrue);
              expect(access.snapshot(), same(before));
              expect(access.mask(), 0);
              expect(_switch(t, bridge).value, isFalse);
              expect(_switch(t, bridge).onChanged, isNull);
              expect(bridge.saves, hasLength(1));
              final request = bridge.saves.single;
              expect(request.payload['expectedRevision'], 7);
              expect(
                request.accountContext!.toJson(),
                _Bridge.account.toJson(),
              );
              expect(
                request.payload[kind == 'friend' ? 'fields' : 'locations'],
                8,
              );
              if (kind == 'friend') {
                expect(
                  request.payload['operationId'],
                  matches(RegExp(r'^[0-9a-f]{32}$')),
                );
              } else {
                expect(request.payload['identityStamp'], 'a' * 64);
              }
              final phase = t.widget(find.byType(HelpSupportWaiting)).key;
              await _frames(t, count: 3);
              expect(t.widget(find.byType(HelpSupportWaiting)).key, phase);
              expect(bridge.saves, hasLength(1));
              await bridge.acknowledgeSave(0);
              await _frames(t);
              expect(access.mask(), 8);
              expect(access.canEdit(), isTrue);
              expect(access.snapshot()!['revision'], 8);
              expect(_switch(t, bridge).value, isTrue);
              expect(find.byType(HelpSupportWaiting), findsNothing);
              expect(bridge.reads, hasLength(1));
              expect(t.takeException(), isNull);
            } finally {
              await _close(t, bridge);
              semantics.dispose();
            }
          },
          timeout: _timeout,
        );
      }

      testWidgets(
        '$suite $kind pointer draft edit follows actual keyboard transaction save source',
        (t) async {
          final bridge = _Bridge(kind);
          final drafts = PrivacyPageDrafts();
          try {
            final access = await _ready(t, bridge, suite, drafts: drafts);
            await _toggle(t, bridge, 'pointer');
            await _frames(t, count: 2);
            expect(drafts.dirty, isTrue);
            expect(bridge.saves, isEmpty);
            expect(access.mask(), 0);
            expect(_switch(t, bridge).value, isTrue);
            await act(
              t,
              find.byKey(const Key('3du-draft-save')),
              'keyboard',
              '保存草稿',
            );
            await _frames(t, count: 2);
            expect(bridge.saves, hasLength(1));
            expect(access.mask(), 0);
            expect(drafts.saving, isTrue);
            _waiting(t, InteractionSource.keyboard);
            await bridge.acknowledgeSave(0);
            await _frames(t);
            expect(access.mask(), 8);
            expect(drafts.saving, isFalse);
            expect(drafts.dirty, isFalse);
            expect(drafts.failed, isFalse);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await _close(t, bridge);
            drafts.dispose();
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $kind same-frame saves retain admitted request source and fresh observer phase',
        (t) async {
          final bridge = _Bridge(kind);
          try {
            final access = await _ready(t, bridge, suite);
            Key? previousPhase;
            for (final source in [
              InteractionSource.keyboard,
              InteractionSource.pointer,
            ]) {
              final index = bridge.saves.length;
              final target = index == 0 ? 8 : 0;
              final accepted = runStarBridgeActivation<void>(
                source,
                () => access.save(target),
              );
              // No frame between admission and the second old callback. The
              // controller's existing busy guard rejects the second save.
              await runStarBridgeActivation<void>(
                source == InteractionSource.keyboard
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
                () => access.save(4),
              );
              await _frames(t, count: 2);
              _waiting(t, source);
              final phase = t.widget(find.byType(HelpSupportWaiting)).key;
              if (previousPhase != null) expect(phase, isNot(previousPhase));
              previousPhase = phase;
              expect(bridge.saves, hasLength(index + 1));
              expect(
                bridge.saves[index].payload[kind == 'friend'
                    ? 'fields'
                    : 'locations'],
                target,
              );
              await bridge.acknowledgeSave(index);
              await accepted;
              await _frames(t);
              expect(access.mask(), target);
              expect(find.byType(HelpSupportWaiting), findsNothing);
            }
            expect(bridge.saves, hasLength(2));
            expect(bridge.reads, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            await _close(t, bridge);
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $kind live reduce stops decoration without relabeling or cancelling save',
        (t) async {
          final bridge = _Bridge(kind);
          try {
            final access = await _ready(t, bridge, suite);
            await _toggle(t, bridge, 'pointer');
            await _frames(t, count: 2);
            _waiting(t, InteractionSource.pointer);
            final phase = t.widget(find.byType(HelpSupportWaiting)).key;
            final state = t.state(
              find.byType(
                kind == 'friend'
                    ? FriendSharingSetting
                    : GameIdVisibilitySetting,
              ),
            );
            await t.pumpWidget(_app(bridge, suite, reduce: true));
            await t.pump(const Duration(milliseconds: 16));
            expect(
              t.state(
                find.byType(
                  kind == 'friend'
                      ? FriendSharingSetting
                      : GameIdVisibilitySetting,
                ),
              ),
              same(state),
            );
            _waiting(t, InteractionSource.pointer, reduce: true);
            expect(t.widget(find.byType(HelpSupportWaiting)).key, phase);
            expect(access.busy(), isTrue);
            expect(access.mask(), 0);
            expect(bridge.saves, hasLength(1));
            await bridge.acknowledgeSave(0);
            await _frames(t);
            expect(access.mask(), 8);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await _close(t, bridge);
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $kind ordinary refresh stays non-loading and keeps existing values editable',
        (t) async {
          final bridge = _Bridge(kind);
          try {
            final access = await _ready(t, bridge, suite);
            final before = access.snapshot();
            final refresh = runStarBridgeActivation<void>(
              InteractionSource.keyboard,
              access.refresh,
            );
            await _frames(t, count: 2);
            expect(bridge.reads, hasLength(2));
            expect(access.busy(), isFalse);
            expect(access.canEdit(), isTrue);
            expect(access.snapshot(), same(before));
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(_switch(t, bridge).onChanged, isNotNull);
            await bridge.reply(bridge.reads.last, bridge.snapshot());
            await refresh;
            await _frames(t);
            expect(access.mask(), 0);
            expect(bridge.saves, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await _close(t, bridge);
          }
        },
        timeout: _timeout,
      );

      testWidgets(
        '$suite $kind keyboard initial viewport is static without extra controller or reads',
        (t) async {
          final bridge = _Bridge(kind);
          try {
            size(t, const Size(1000, 900));
            await t.pumpWidget(_app(bridge, suite, keyboardOpening: true));
            await _frames(t, count: 2);
            expect(bridge.reads, hasLength(1));
            expect(find.byType(HelpSupportWaiting), findsOneWidget);
            expect(find.byType(SuiteProgressBar), findsNothing);
            expect(find.byType(LinearProgressIndicator), findsNothing);
            expect(_Access.of(t, bridge).busy(), isTrue);
            await bridge.reply(bridge.reads.single, bridge.snapshot());
            await _frames(t);
            expect(find.byType(HelpSupportWaiting), findsNothing);
            expect(_Access.of(t, bridge).canEdit(), isTrue);
            expect(bridge.reads, hasLength(1));
            expect(bridge.saves, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await _close(t, bridge);
          }
        },
        timeout: _timeout,
      );
    }
  }
}
