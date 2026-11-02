import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/settings/event_scope_editor.dart';
import 'package:starbridge_flutter/features/settings/event_sharing_controller.dart';
import 'package:starbridge_flutter/features/settings/event_sharing_page.dart';
import 'package:starbridge_flutter/features/settings/help_support_action.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/privacy_page_drafts.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3do_test.dart' show act, loadFonts, scopedApp, size;

const _timeout = Timeout(Duration(seconds: 45));

Future<void> eventMotionFrames(WidgetTester t, {int count = 4}) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// A wire fixture only. The real page creates the single real controller.
class EventMotionBridge {
  EventMotionBridge() {
    final pair = InMemoryBridgeConnection.createPair();
    host = pair.host;
    session = BridgeClientSession(connection: pair.client, sessionGeneration: 4)
      ..acceptHostCapabilities(const ['eventSharing.settings']);
    subscription = host.incoming.listen((request) {
      requests.add(request);
      if (request.name == 'account.getCurrent') {
        unawaited(
          reply(request, const {'schemaVersion': 1, 'state': 'signedIn'}),
        );
      }
    });
  }
  static const joined = '2026-09-01T00:00:00.1234567+00:00';
  late final BridgeConnection host;
  late final BridgeClientSession session;
  late final StreamSubscription<BridgeEnvelope> subscription;
  final requests = <BridgeEnvelope>[];
  List<BridgeEnvelope> named(String name) =>
      requests.where((r) => r.name == name).toList();
  List<BridgeEnvelope> get reads => named('eventSharing.read');
  List<BridgeEnvelope> get saves => named('eventSharing.save');
  List<BridgeEnvelope> get directories => named('privacy.communityTargets');
  Map<String, Object?> snapshot({BridgeEnvelope? save}) => {
    'state': 'inactive',
    'snapshot': {
      'schemaVersion': 1,
      'revision': save == null
          ? 1
          : (save.payload['expectedRevision'] as int) + 1,
      'operationId': save?.payload['operationId'] ?? '0' * 32,
      'appliedAt': '2026-10-16T00:00:00Z',
      'publicationEnabled': save?.payload['publicationEnabled'] ?? true,
      'settings':
          save?.payload['settings'] ??
          {
            'room': {'enabled': true, 'selectedTypes': 47},
            'communities': [
              for (final code in ['A', 'B'])
                {
                  'code': code,
                  'joinedAt': joined,
                  'choice': {'enabled': true, 'selectedTypes': 47},
                },
            ],
          },
    },
  };
  Map<String, Object?> directory() => {
    'schemaVersion': 2,
    'primaryFleetCode': null,
    'communities': [
      for (final code in ['A', 'B'])
        {'code': code, 'name': 'Test Community $code', 'joinedAt': joined},
    ],
  };
  Future<void> reply(
    BridgeEnvelope request,
    Map<String, Object?> payload, {
    bool failed = false,
  }) => host.send(
    BridgeEnvelope(
      protocolVersion: 1,
      messageType: 'response',
      name: request.name,
      correlationId: request.correlationId,
      sessionGeneration: request.sessionGeneration,
      accountContext: const BridgeAccountContext(
        environment: 'test',
        authority: 'scm',
        subject: '3dv-synthetic',
      ),
      status: failed ? 'error' : 'ok',
      error: failed
          ? const BridgeErrorBody(
              code: 'events.write_unconfirmed',
              message: 'fixture refusal',
              retryable: false,
            )
          : null,
      payload: payload,
    ),
  );
  Future<void> close() async {
    await subscription.cancel();
    await session.close();
    await host.close();
  }
}

Widget eventMotionApp(
  EventMotionBridge bridge,
  InteractionSuite suite, {
  PrivacyPageDrafts? drafts,
  bool reduce = false,
  bool light = false,
  bool themeOnly = false,
  double scale = 1,
  Locale locale = const Locale('zh', 'CN'),
}) {
  Widget content = Column(
    children: [
      Expanded(child: EventSharingPage(session: bridge.session)),
      if (drafts != null)
        HelpSupportAction(
          controlKey: const Key('3dv-draft-save'),
          onActivate: (source) =>
              runStarBridgeActivation<void>(source, () async {
                await drafts.save();
              }),
          child: const Text('保存草稿'),
        ),
    ],
  );
  if (drafts != null) {
    content = PrivacyDraftScope(drafts: drafts, child: content);
  }
  final body = content;
  final base = scopedApp(
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: SizedBox.expand(child: body),
      ),
    ),
    suite,
    reduce: reduce,
    light: light,
    locale: locale,
  ) as MaterialApp;
  return themeOnly
      ? MaterialApp(
          theme: base.theme,
          themeAnimationDuration: Duration.zero,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          home: base.home,
        )
      : base;
}

EventSharingController eventMotionController(WidgetTester t) {
  final dynamic state = t.state(find.byType(EventSharingPage));
  return state.controller as EventSharingController;
}

Future<EventSharingController> eventMotionReady(
  WidgetTester t,
  EventMotionBridge bridge,
) async {
  await eventMotionFrames(t, count: 2);
  expect(bridge.reads, hasLength(1));
  await bridge.reply(bridge.reads.single, bridge.snapshot());
  await eventMotionFrames(t, count: 2);
  expect(bridge.directories, hasLength(1));
  await bridge.reply(bridge.directories.single, bridge.directory());
  await eventMotionFrames(t);
  final controller = eventMotionController(t);
  expect(controller.canEdit, isTrue);
  return controller;
}

Finder eventMotionControl(String scope, String control) => find.byKey(
  Key(
    control == 'master'
        ? 'privacy-scope-event-$scope-audience-events-enabled'
        : 'privacy-scope-event-$scope-field-$control',
  ),
);

Future<void> eventMotionActivate(
  WidgetTester t,
  Finder target,
  String source,
) async {
  await t.ensureVisible(target);
  await t.pump();
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'keyboard') {
    final widget = t.widget(target);
    if (widget is StarBridgeCheckboxTile) {
      final control = t.widget(
        find
            .descendant(
              of: target,
              matching: find.byWidgetPredicate(
                (w) => w is Checkbox || w is SuiteCheckbox,
              ),
            )
            .first,
      );
      final focus = switch (control) {
        Checkbox value => value.focusNode!,
        SuiteCheckbox value => value.focusNode!,
        _ => throw StateError('Missing audience checkbox'),
      };
      focus.requestFocus();
    } else {
      t
          .widget<SuitePressable>(
            find
                .descendant(of: target, matching: find.byType(SuitePressable))
                .first,
          )
          .focusNode!
          .requestFocus();
    }
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final nodes = <SemanticsNode>[];
    void visit(SemanticsNode node) {
      if (node.getSemanticsData().hasAction(SemanticsAction.tap)) {
        nodes.add(node);
      }
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(t.getSemantics(target));
    expect(
      nodes,
      hasLength(1),
      reason: 'Activate this scope, not another identical label.',
    );
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      SemanticsAction.tap,
    );
  }
  await t.pump();
}

void _waiting(WidgetTester t, InteractionSource source, {bool reduce = false}) {
  final wait = find.byType(HelpSupportWaiting);
  expect(wait, findsOneWidget);
  final widget = t.widget<HelpSupportWaiting>(wait);
  expect(widget.source, source);
  final strings = AppStrings.of(t.element(wait));
  expect(
    widget.label,
    contains(strings.text('settings.privacy.events.pending')),
  );
  expect(widget.label, isNot(contains(strings.text('privacy.local.saving'))));
  expect(find.byType(LinearProgressIndicator), findsNothing);
  expect(
    find.byType(SuiteProgressBar),
    reduce || source == InteractionSource.keyboard
        ? findsNothing
        : findsOneWidget,
  );
}

Future<void> eventMotionClose(WidgetTester t, EventMotionBridge bridge) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.runAsync(bridge.close);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite actual event page initial read and directory retain approved neutral waiting',
      (t) async {
        size(t, const Size(1000, 900));
        final bridge = EventMotionBridge();
        try {
          await t.pumpWidget(eventMotionApp(bridge, suite));
          await eventMotionFrames(t, count: 2);
          expect(bridge.reads, hasLength(1));
          expect(find.byType(HelpSupportWaiting), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          await bridge.reply(bridge.reads.single, bridge.snapshot());
          await eventMotionFrames(t, count: 2);
          expect(bridge.directories, hasLength(1));
          expect(find.byType(HelpSupportWaiting), findsOneWidget);
          await bridge.reply(bridge.directories.single, bridge.directory());
          await eventMotionFrames(t);
          expect(find.byType(HelpSupportWaiting), findsNothing);
          expect(bridge.saves, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          await t.runAsync(bridge.close);
        }
      },
      timeout: _timeout,
    );

    for (final control in ['master', 'life']) {
      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '$suite $control $source preserves CAS scopes and receipt while real control is pending',
          (t) async {
            final semantics = t.ensureSemantics();
            final bridge = EventMotionBridge();
            try {
              size(t, const Size(1000, 900));
              await t.pumpWidget(eventMotionApp(bridge, suite));
              final controller = await eventMotionReady(t, bridge);
              final before = controller.snapshot;
              final target = eventMotionControl('room', control);
              await eventMotionActivate(t, target, source);
              await eventMotionFrames(t, count: 2);
              _waiting(
                t,
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              expect(controller.snapshot, same(before));
              expect(controller.busy, isTrue);
              expect(controller.canEdit, isFalse);
              expect(
                controller.choice(null),
                const EventSharingChoice(enabled: true, selectedTypes: 47),
              );
              expect(bridge.saves, hasLength(1));
              final request = bridge.saves.single;
              expect(
                request.payload.keys,
                unorderedEquals([
                  'schemaVersion',
                  'expectedRevision',
                  'operationId',
                  'publicationEnabled',
                  'settings',
                ]),
              );
              expect(request.payload['expectedRevision'], 1);
              expect(
                request.payload['operationId'],
                matches(RegExp(r'^[0-9a-f]{32}$')),
              );
              expect(request.payload['publicationEnabled'], isTrue);
              final settings = request.payload['settings'] as Map;
              expect(settings['room'], {
                'enabled': control != 'master',
                'selectedTypes': control == 'master' ? 47 : 15,
              });
              final communities = settings['communities'] as List;
              expect(communities, [
                for (final code in ['A', 'B'])
                  {
                    'code': code,
                    'joinedAt': EventMotionBridge.joined,
                    'choice': {'enabled': true, 'selectedTypes': 47},
                  },
              ]);
              if (control == 'master') {
                expect(
                  t.widget<StarBridgeCheckboxTile>(target).onChanged,
                  isNull,
                );
              } else {
                expect(t.widget<StarBridgeSwitch>(target).onChanged, isNull);
              }
              await bridge.reply(request, bridge.snapshot(save: request));
              await eventMotionFrames(t);
              expect(controller.snapshot!['revision'], 2);
              expect(controller.snapshot!['appliedAt'], '2026-10-16T00:00:00Z');
              expect(controller.choice(null).enabled, control != 'master');
              expect(
                controller.choice(null).selectedTypes,
                control == 'master' ? 47 : 15,
              );
              expect(controller.canEdit, isTrue);
              expect(find.byType(HelpSupportWaiting), findsNothing);
              expect(bridge.reads, hasLength(1));
              expect(t.takeException(), isNull);
            } finally {
              await eventMotionClose(t, bridge);
              semantics.dispose();
            }
          },
          timeout: _timeout,
        );
      }
    }

    testWidgets(
      '$suite pointer community draft follows actual keyboard transaction source',
      (t) async {
        final bridge = EventMotionBridge();
        final drafts = PrivacyPageDrafts();
        try {
          size(t, const Size(1000, 900));
          await t.pumpWidget(eventMotionApp(bridge, suite, drafts: drafts));
          final controller = await eventMotionReady(t, bridge);
          await eventMotionActivate(
            t,
            eventMotionControl('B', 'life'),
            'pointer',
          );
          await eventMotionFrames(t, count: 2);
          expect(drafts.dirty, isTrue);
          expect(bridge.saves, isEmpty);
          expect(controller.choice('B').selectedTypes, 47);
          await act(
            t,
            find.byKey(const Key('3dv-draft-save')),
            'keyboard',
            '保存草稿',
          );
          await eventMotionFrames(t, count: 2);
          _waiting(t, InteractionSource.keyboard);
          expect(drafts.saving, isTrue);
          expect(bridge.saves, hasLength(1));
          final request = bridge.saves.single;
          final rows =
              (request.payload['settings'] as Map)['communities'] as List;
          expect(rows[1]['joinedAt'], EventMotionBridge.joined);
          expect(rows[1]['choice'], {'enabled': true, 'selectedTypes': 15});
          expect(rows[0]['choice'], {'enabled': true, 'selectedTypes': 47});
          await bridge.reply(request, bridge.snapshot(save: request));
          await eventMotionFrames(t);
          expect(drafts.dirty, isFalse);
          expect(drafts.saving, isFalse);
          expect(drafts.failed, isFalse);
          expect(controller.choice('B').selectedTypes, 15);
          expect(find.byType(HelpSupportWaiting), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await eventMotionClose(t, bridge);
          drafts.dispose();
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite same-frame request admission keeps first source and new busy phase',
      (t) async {
        final bridge = EventMotionBridge();
        try {
          size(t, const Size(1000, 900));
          await t.pumpWidget(eventMotionApp(bridge, suite));
          final controller = await eventMotionReady(t, bridge);
          Key? previous;
          for (final source in [
            InteractionSource.keyboard,
            InteractionSource.pointer,
          ]) {
            final index = bridge.saves.length;
            final accepted = runStarBridgeActivation<bool>(
              source,
              () => controller.saveChoices({
                null: EventSharingChoice(
                  enabled: index != 0,
                  selectedTypes: 47,
                ),
              }),
            );
            final rejected = await runStarBridgeActivation<bool>(
              source == InteractionSource.keyboard
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
              () => controller.saveChoices({
                null: const EventSharingChoice(enabled: true, selectedTypes: 1),
              }),
            );
            expect(rejected, isFalse);
            await eventMotionFrames(t, count: 2);
            expect(bridge.saves, hasLength(index + 1));
            _waiting(t, source);
            final key = t.widget(find.byType(HelpSupportWaiting)).key;
            if (previous != null) expect(key, isNot(previous));
            previous = key;
            await bridge.reply(
              bridge.saves[index],
              bridge.snapshot(save: bridge.saves[index]),
            );
            expect(await accepted, isTrue);
            await eventMotionFrames(t);
            expect(find.byType(HelpSupportWaiting), findsNothing);
          }
          expect(bridge.saves, hasLength(2));
          expect(bridge.reads, hasLength(1));
          expect(t.takeException(), isNull);
        } finally {
          await eventMotionClose(t, bridge);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite live reduce keeps owner pending and source but stops wait decoration',
      (t) async {
        final bridge = EventMotionBridge();
        try {
          size(t, const Size(1000, 900));
          await t.pumpWidget(eventMotionApp(bridge, suite));
          final controller = await eventMotionReady(t, bridge);
          await eventMotionActivate(
            t,
            eventMotionControl('B', 'life'),
            'pointer',
          );
          await eventMotionFrames(t, count: 2);
          _waiting(t, InteractionSource.pointer);
          final key = t.widget(find.byType(HelpSupportWaiting)).key;
          await t.pumpWidget(eventMotionApp(bridge, suite, reduce: true));
          await t.pump(const Duration(milliseconds: 16));
          _waiting(t, InteractionSource.pointer, reduce: true);
          expect(t.widget(find.byType(HelpSupportWaiting)).key, key);
          expect(controller.busy, isTrue);
          expect(controller.choice('B').selectedTypes, 47);
          expect(bridge.saves, hasLength(1));
          await bridge.reply(
            bridge.saves.single,
            bridge.snapshot(save: bridge.saves.single),
          );
          await eventMotionFrames(t);
          expect(controller.choice('B').selectedTypes, 15);
          expect(find.byType(HelpSupportWaiting), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await eventMotionClose(t, bridge);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite periodic read retains original busy disabling and neutral programmatic wait',
      (t) async {
        final bridge = EventMotionBridge();
        try {
          size(t, const Size(1000, 900));
          await t.pumpWidget(eventMotionApp(bridge, suite));
          final controller = await eventMotionReady(t, bridge);
          final before = controller.snapshot;
          await t.pump(const Duration(seconds: 15));
          await eventMotionFrames(t, count: 2);
          expect(bridge.reads, hasLength(2));
          expect(controller.busy, isTrue);
          expect(controller.canEdit, isFalse);
          expect(controller.snapshot, same(before));
          _waiting(t, InteractionSource.programmatic);
          expect(
            t
                .widget<StarBridgeSwitch>(eventMotionControl('B', 'life'))
                .onChanged,
            isNull,
          );
          await bridge.reply(bridge.reads.last, bridge.snapshot());
          await eventMotionFrames(t, count: 2);
          expect(bridge.directories, hasLength(2));
          _waiting(t, InteractionSource.programmatic);
          await bridge.reply(bridge.directories.last, bridge.directory());
          await eventMotionFrames(t);
          expect(controller.canEdit, isTrue);
          expect(bridge.saves, isEmpty);
          expect(find.byType(HelpSupportWaiting), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await eventMotionClose(t, bridge);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$suite refused save leaves original receipt and explicit keyboard refresh owns new wait',
      (t) async {
        final bridge = EventMotionBridge();
        try {
          size(t, const Size(1000, 900));
          await t.pumpWidget(eventMotionApp(bridge, suite));
          final controller = await eventMotionReady(t, bridge);
          final before = controller.snapshot;
          await eventMotionActivate(
            t,
            eventMotionControl('B', 'life'),
            'pointer',
          );
          await eventMotionFrames(t, count: 2);
          await bridge.reply(bridge.saves.single, const {}, failed: true);
          await eventMotionFrames(t);
          expect(controller.snapshot, same(before));
          expect(controller.error, 'events.write_unconfirmed');
          expect(controller.canEdit, isFalse);
          expect(find.byType(HelpSupportWaiting), findsNothing);
          final strings = AppStrings.of(
            t.element(find.byType(EventSharingPage)),
          );
          expect(
            find.text(strings.text('settings.privacy.events.unavailable')),
            findsOneWidget,
          );
          final refresh = runStarBridgeActivation<void>(
            InteractionSource.keyboard,
            controller.refresh,
          );
          await eventMotionFrames(t, count: 2);
          _waiting(t, InteractionSource.keyboard);
          expect(bridge.saves, hasLength(1));
          await bridge.reply(bridge.reads.last, bridge.snapshot());
          await eventMotionFrames(t, count: 2);
          await bridge.reply(bridge.directories.last, bridge.directory());
          await refresh;
          await eventMotionFrames(t);
          expect(controller.error, isNull);
          expect(controller.choice('B').selectedTypes, 47);
          expect(controller.canEdit, isTrue);
          expect(bridge.saves, hasLength(1));
          expect(t.takeException(), isNull);
        } finally {
          await eventMotionClose(t, bridge);
        }
      },
      timeout: _timeout,
    );
  }
}
