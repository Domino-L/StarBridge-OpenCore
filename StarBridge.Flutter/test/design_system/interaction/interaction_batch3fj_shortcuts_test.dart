import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_shortcuts.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/communities/community_shortcuts_test.dart'
    show QueuedPort;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3i_test.dart' show scopedApp;

Future<void> shortcutsFrames(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
  await t.pump(const Duration(milliseconds: 50));
}

class ShortcutsPort extends QueuedPort {
  ShortcutsPort() {
    queued = true;
  }
  final requests = <(String, String, String?, String?, InteractionSource)>[];
  @override
  Future<CommunityDirectory> read({
    required String view,
    required String query,
    String? after,
    String? filters,
  }) {
    requests.add((
      view,
      query,
      after,
      filters,
      currentStarBridgeActivationSource,
    ));
    return super.read(view: view, query: query, after: after, filters: filters);
  }
}

class ShortcutsProbe {
  ShortcutsProbe(this.suite, this.module);
  final InteractionSuite suite;
  CommunitiesModule module;
  bool reduce = false, light = false, shown = true, iconOnly = false;
  final activations = <InteractionSource>[];
  final guards = <Completer<bool>>[];
  late StateSetter update;
  Widget shortcuts() => CommunityShortcuts(
    module: module,
    iconOnly: iconOnly,
    selected: true,
    activate: () {
      activations.add(currentStarBridgeActivationSource);
      final gate = Completer<bool>();
      guards.add(gate);
      return gate.future;
    },
  );
  Widget app() => StatefulBuilder(
    builder: (_, state) {
      update = state;
      return scopedApp(
        Semantics(
          explicitChildNodes: true,
          child: SizedBox(
            width: 300,
            child: shown ? shortcuts() : const Text('Shortcuts left'),
          ),
        ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

Future<void> shortcutsActivate(
  WidgetTester t,
  Finder target,
  String label,
  String input,
) async {
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  if (input == 'reader') {
    final nodes = exposedNodes(t).where((n) {
      final data = n.getSemanticsData();
      return data.label == label && data.hasAction(ui.SemanticsAction.tap);
    }).toList();
    expect(nodes, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      ui.SemanticsAction.tap,
    );
  } else if (input == 'keyboard') {
    final widget = t.widget(target);
    FocusNode? node = widget is ButtonStyleButton
        ? widget.focusNode
        : widget is SuitePressable
        ? widget.focusNode
        : null;
    if (node == null) {
      final focus = find.descendant(
        of: target,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Focus &&
              w.focusNode != null &&
              w.focusNode!.canRequestFocus &&
              !w.focusNode!.skipTraversal,
        ),
      );
      expect(focus, findsOneWidget);
      node = t.widget<Focus>(focus).focusNode!;
    }
    FocusScope.of(t.element(target)).unfocus();
    await t.pump();
    await t.pump();
    for (var i = 0; !node.hasPrimaryFocus && i < 40; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.pump();
    }
    expect(
      node.hasPrimaryFocus,
      isTrue,
      reason: '$node\n${FocusManager.instance.toStringDeep()}',
    );
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await t.tap(target);
  }
  await shortcutsFrames(t);
}

void expectShortcutsWaiting(
  WidgetTester t,
  InteractionSuite suite, {
  required InteractionSource source,
  required bool opening,
  bool reduce = false,
}) {
  final activity = find.byType(SocialReadActivity);
  expect(activity, findsOneWidget);
  final waiting = t.widget<SocialReadActivity>(activity);
  expect(waiting.source, source);
  expect(waiting.opening, opening);
  expect(waiting.height, 4);
  final marker = t.widget<LinearProgressIndicator>(
    find.descendant(
      of: activity,
      matching: find.byType(LinearProgressIndicator),
    ),
  );
  final animate =
      !reduce &&
      source != InteractionSource.keyboard &&
      (opening || source == InteractionSource.pointer);
  expect(
    marker.value,
    animate &&
            (suite == InteractionSuite.standard ||
                suite == InteractionSuite.glow)
        ? null
        : .5,
  );
  final labels = exposedNodes(t)
      .where((n) => n.getSemanticsData().label == '正在读取社区组织…')
      .toList();
  expect(labels, hasLength(1));
  expect(
    labels.single.getSemanticsData().value,
    isEmpty,
    reason: 'half-track is not 50 percent complete',
  );
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '3fj $suite $input real joined retry, cursor and guarded activation',
        (t) async {
          size(t, const Size(1000, 1000));
          final semantics = t.ensureSemantics();
          final port = ShortcutsPort();
          final module = CommunitiesModule(port);
          final p = ShortcutsProbe(suite, module);
          try {
            await t.pumpWidget(p.app());
            await shortcutsFrames(t);
            expect(port.reads, hasLength(1));
            expectShortcutsWaiting(
              t,
              suite,
              source: InteractionSource.programmatic,
              opening: true,
            );
            final initialKey = t
                .widget<SocialReadActivity>(find.byType(SocialReadActivity))
                .key;
            port.reads.single.completeError(
              const CommunityFailure('readTransient'),
            );
            await shortcutsFrames(t);
            expect(find.byType(SocialReadActivity), findsNothing);
            expect(module.joined, isEmpty);
            final origin = input == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard;
            await shortcutsActivate(
              t,
              find.byKey(const Key('community-shortcuts-retry')),
              '重试',
              input,
            );
            expect(port.reads, hasLength(2));
            expect(port.requests.last, ('mine', '', null, null, origin));
            expectShortcutsWaiting(t, suite, source: origin, opening: false);
            expect(
              t.widget<SocialReadActivity>(find.byType(SocialReadActivity)).key,
              isNot(initialKey),
            );
            expect(
              find.byKey(const Key('community-shortcuts-retry')),
              findsNothing,
              reason: 'original module clears readTransient while retry is admitted',
            );
            p.update(() {
              p.reduce = true;
              p.light = true;
            });
            await t.pump();
            await t.pump();
            expectShortcutsWaiting(
              t,
              suite,
              source: origin,
              opening: false,
              reduce: true,
            );
            port.reads.last.complete(
              CommunityDirectory('mine', '', [port.rows[0]], next: 'cursor-2'),
            );
            await shortcutsFrames(t);
            expect(module.joinedLoaded, isTrue);
            expect(module.joined.map((row) => row.key), [port.rows[0].key]);
            expect(find.byType(SocialReadActivity), findsNothing);
            final hints = t.widgetList<StarBridgeTooltip>(
              find.byType(StarBridgeTooltip),
            );
            expect(hints.single.message, port.rows[0].name);
            p.update(() => p.reduce = false);
            await shortcutsFrames(t);
            final more = find.byKey(const Key('community-shortcuts-more'));
            await shortcutsActivate(t, more, '显示更多', input);
            expect(port.reads, hasLength(3));
            expect(port.requests.last, ('mine', '', 'cursor-2', null, origin));
            expect(module.joined.map((row) => row.key), [port.rows[0].key]);
            expect(
              find.byType(SocialReadActivity),
              findsNothing,
              reason: 'existing rows stay, no empty loading replacement',
            );
            final moreAdapter = find.ancestor(
              of: more,
              matching: find.byType(StarBridgeActionButton),
            );
            expect(
              t.widget<StarBridgeActionButton>(moreAdapter).onActivate,
              isNull,
            );
            final exposedMore = exposedNodes(t)
                .where((n) => n.getSemanticsData().label == '显示更多')
                .toList();
            expect(exposedMore, hasLength(1));
            expect(
              exposedMore.single.getSemanticsData().hasAction(
                ui.SemanticsAction.tap,
              ),
              isFalse,
            );
            await t.tapAt(t.getCenter(more));
            await t.pump();
            expect(port.reads, hasLength(3));
            // Exercise the unchanged 3-second observer with the real request held.
            await t.pump(const Duration(milliseconds: 3100));
            expect(port.reads, hasLength(3));
            port.reads.last.complete(
              CommunityDirectory('mine', '', [port.rows[1]]),
            );
            await shortcutsFrames(t);
            expect(module.joined.map((row) => row.key), [
              port.rows[0].key,
              port.rows[1].key,
            ]);
            expect(
              find.byKey(const Key('community-shortcuts-more')),
              findsNothing,
            );
            final row = find.byKey(
              ValueKey('community-shortcut-${port.rows[0].key}'),
            );
            await shortcutsActivate(t, row, port.rows[0].name, input);
            expect(p.activations, [origin]);
            expect(module.selected, isNull);
            p.guards.single.complete(false);
            await shortcutsFrames(t);
            expect(module.selected, isNull);
            await shortcutsActivate(t, row, port.rows[0].name, input);
            expect(p.activations, [origin, origin]);
            p.guards.last.complete(true);
            await shortcutsFrames(t);
            expect(module.selected?.key, port.rows[0].key);
            expect(port.writes, isEmpty);
            expect(port.reads, hasLength(3));
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            module.dispose();
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '3fj $suite actual keyboard opening inherits route and preserves native height',
      (t) async {
        size(t, const Size(1000, 900));
        final semantics = t.ensureSemantics();
        final port = ShortcutsPort();
        final module = CommunitiesModule(port);
        try {
          await t.pumpWidget(
            scopedApp(
              Builder(
                builder: (context) => StarBridgeActionButton(
                  controlKey: const Key('open-shortcuts'),
                  onActivate: (source) => unawaited(
                    showStarBridgeDialog<void>(
                      context,
                      source: source,
                      builder: (_) => AlertDialog(
                        content: SizedBox(
                          width: 300,
                          height: 260,
                          child: CommunityShortcuts(
                            module: module,
                            iconOnly: false,
                            selected: false,
                            activate: () async => true,
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open shortcuts'),
                ),
              ),
              suite,
            ),
          );
          await shortcutsFrames(t);
          await shortcutsActivate(
            t,
            find.byKey(const Key('open-shortcuts')),
            'Open shortcuts',
            'keyboard',
          );
          expect(port.reads, hasLength(1));
          final activity = find.byType(SocialReadActivity);
          expect(t.widget<SocialReadActivity>(activity).opening, isTrue);
          final marker = t.widget<LinearProgressIndicator>(
            find.descendant(
              of: activity,
              matching: find.byType(LinearProgressIndicator),
            ),
          );
          expect(marker.value, .5);
          expect(marker.minHeight, 4);
          port.reads.single.complete(CommunityDirectory('mine', '', const []));
          await shortcutsFrames(t);
          expect(find.byType(SocialReadActivity), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          module.dispose();
          semantics.dispose();
        }
      },
    );

    testWidgets(
      '3fj $suite owner swap detaches old busy observations and late result',
      (t) async {
        size(t, const Size(1000, 900));
        final oldPort = ShortcutsPort(), nextPort = ShortcutsPort();
        final old = CommunitiesModule(oldPort),
            next = CommunitiesModule(nextPort);
        final p = ShortcutsProbe(suite, old);
        try {
          await t.pumpWidget(p.app());
          await shortcutsFrames(t);
          final first = t
              .widget<SocialReadActivity>(find.byType(SocialReadActivity))
              .key;
          p.update(() => p.module = next);
          await shortcutsFrames(t);
          expect(nextPort.reads, hasLength(1));
          final second = t
              .widget<SocialReadActivity>(find.byType(SocialReadActivity))
              .key;
          expect(second, isNot(first));
          oldPort.reads.single.complete(
            CommunityDirectory('mine', '', [oldPort.rows[0]]),
          );
          await shortcutsFrames(t);
          expect(find.text(oldPort.rows[0].name), findsNothing);
          expect(find.byType(SocialReadActivity), findsOneWidget);
          nextPort.reads.single.complete(
            CommunityDirectory('mine', '', [nextPort.rows[1]]),
          );
          await shortcutsFrames(t);
          expect(find.text(nextPort.rows[1].name), findsOneWidget);
          expect(next.selected, isNull);
          expect(p.activations, isEmpty);
          oldPort.changes.add(null);
          await shortcutsFrames(t);
          expect(oldPort.reads, hasLength(1));
          expect(nextPort.reads, hasLength(1));
          expect(find.text(nextPort.rows[1].name), findsOneWidget);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          old.dispose();
          next.dispose();
        }
      },
    );

    testWidgets(
      '3fj $suite leaving during original activation guard prevents late open',
      (t) async {
        size(t, const Size(1000, 900));
        final port = ShortcutsPort();
        final module = CommunitiesModule(port);
        final p = ShortcutsProbe(suite, module);
        try {
          await t.pumpWidget(p.app());
          await shortcutsFrames(t);
          port.reads.single.complete(
            CommunityDirectory('mine', '', [port.rows[0]]),
          );
          await shortcutsFrames(t);
          await shortcutsActivate(
            t,
            find.byKey(ValueKey('community-shortcut-${port.rows[0].key}')),
            port.rows[0].name,
            'pointer',
          );
          expect(p.guards, hasLength(1));
          expect(module.selected, isNull);
          p.update(() => p.shown = false);
          await shortcutsFrames(t);
          p.guards.single.complete(true);
          await shortcutsFrames(t);
          expect(module.selected, isNull);
          expect(find.text('Shortcuts left'), findsOneWidget);
          expect(p.activations, hasLength(1));
          expect(port.reads, hasLength(1));
          expect(port.writes, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          module.dispose();
        }
      },
    );
  }
}
