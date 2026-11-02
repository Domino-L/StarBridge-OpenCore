import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';

import 'interaction_batch3bg_test.dart' show SplashProbe;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bg_test.dart' show activate;

List<SemanticsNode> exposedButtons(WidgetTester t) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode n) {
    if (n.isMergedIntoParent) return;
    if (n.getSemanticsData().flagsCollection.isButton) {
      nodes.add(n);
    }
    n.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(t.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!);
  return nodes;
}

void readerTap(WidgetTester t, Finder target) {
  final node = t.getSemantics(target);
  expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
  t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
    node.id,
    ui.SemanticsAction.tap,
  );
}

Widget host(
  Widget child,
  InteractionSuite suite,
  SplashProbe splash, {
  bool reduce = false,
}) => scopedApp(
  Builder(
    builder: (c) => Theme(
      data: Theme.of(c).copyWith(
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(splashFactory: splash),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(splashFactory: splash),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(splashFactory: splash),
        ),
      ),
      child: Center(child: child),
    ),
  ),
  suite,
  reduce: reduce,
);

void main() {
  for (final kind in StarBridgeActionKind.values) {
    testWidgets(
      'standard $kind reader preserves implicit label without native ink',
      (t) async {
        final semantics = t.ensureSemantics();
        try {
          final splash = SplashProbe();
          final calls = <InteractionSource>[];
          await t.pumpWidget(
            host(
              StarBridgeActionButton(
                kind: kind,
                controlKey: const Key('target'),
                onActivate: calls.add,
                child: const Text('测试操作'),
              ),
              InteractionSuite.standard,
              splash,
            ),
          );
          await t.pump();
          expect(
            t
                .getSemantics(find.byKey(const Key('target')))
                .getSemanticsData()
                .label,
            '测试操作',
          );
          readerTap(t, find.byKey(const Key('target')));
          await t.pump();
          expect(calls, [InteractionSource.keyboard]);
          expect(splash.created, 0);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
  for (final suite in InteractionSuite.values) {
    for (final kind in StarBridgeActionKind.values) {
      for (final content in [
        'text',
        'icon-text',
        'tooltip',
        'child-semantics',
        'override',
      ]) {
        testWidgets(
          '$suite $kind $content one reader node and preserved label',
          (t) async {
            final semantics = t.ensureSemantics();
            try {
              final splash = SplashProbe();
              final calls = <InteractionSource>[];
              Widget child = const Text('自动标签');
              if (content == 'icon-text') {
                child = const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Icon(Icons.download), Text('自动标签')],
                );
              }
              if (content == 'tooltip') {
                child = const Tooltip(message: '操作说明', child: Text('自动标签'));
              }
              if (content == 'child-semantics') {
                child = Semantics(
                  label: '辅助名称',
                  excludeSemantics: true,
                  child: const Icon(Icons.download),
                );
              }
              await t.pumpWidget(
                host(
                  StarBridgeActionButton(
                    kind: kind,
                    controlKey: const Key('target'),
                    semanticLabel: content == 'override' ? '显式名称' : null,
                    onActivate: calls.add,
                    child: child,
                  ),
                  suite,
                  splash,
                ),
              );
              await t.pump();
              final nodes = exposedButtons(t);
              expect(nodes.length, 1);
              final data = nodes.single.getSemanticsData();
              expect(
                data.label,
                content == 'override'
                    ? '显式名称'
                    : content == 'child-semantics'
                    ? '辅助名称'
                    : '自动标签',
              );
              expect(data.flagsCollection.isEnabled, ui.Tristate.isTrue);
              if (content == 'tooltip') {
                expect(data.tooltip, '操作说明');
              }
              readerTap(t, find.byKey(const Key('target')));
              await t.pump();
              expect(calls, [InteractionSource.keyboard]);
              expect(splash.created, 0);
              expect(t.takeException(), isNull);
            } finally {
              semantics.dispose();
            }
          },
        );
      }
      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets('$suite $kind $source active commands not coalesced', (
          t,
        ) async {
          final semantics = t.ensureSemantics();
          try {
            final splash = SplashProbe();
            final calls = <InteractionSource>[];
            await t.pumpWidget(
              host(
                StarBridgeActionButton(
                  kind: kind,
                  controlKey: const Key('target'),
                  onActivate: calls.add,
                  child: const Text('操作'),
                ),
                suite,
                splash,
              ),
            );
            await t.pump();
            for (var i = 0; i < 4; i++) {
              await activate(t, source, const Key('target'));
            }
            expect(calls.length, 4);
            expect(
              calls.every(
                (s) =>
                    s ==
                    (source == 'pointer'
                        ? InteractionSource.pointer
                        : InteractionSource.keyboard),
              ),
              isTrue,
            );
            if (suite == InteractionSuite.standard) {
              expect(splash.created, source == 'pointer' ? 4 : 0);
            }
            if (suite != InteractionSuite.standard && source == 'pointer') {
              expect(t.binding.hasScheduledFrame, isTrue);
            }
            await t.pump(const Duration(milliseconds: 600));
          } finally {
            semantics.dispose();
          }
        });
      }
      testWidgets('$suite $kind disabled blocks reader pointer and keyboard', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        final focus = FocusNode();
        try {
          final splash = SplashProbe();
          await t.pumpWidget(
            host(
              StarBridgeActionButton(
                kind: kind,
                controlKey: const Key('target'),
                focusNode: focus,
                onActivate: null,
                child: const Text('不可用'),
              ),
              suite,
              splash,
            ),
          );
          await t.pump();
          final nodes = exposedButtons(t);
          expect(nodes.length, 1);
          final data = nodes.single.getSemanticsData();
          expect(data.label, '不可用');
          expect(data.flagsCollection.isEnabled, ui.Tristate.isFalse);
          expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
          // Disabled advanced controls intentionally ignore the hit test.
          await t.tap(find.byKey(const Key('target')), warnIfMissed: false);
          await t.pump();
          focus.requestFocus();
          await t.pump();
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          expect(splash.created, 0);
          expect(focus.hasFocus, isFalse);
        } finally {
          await t.pumpWidget(const SizedBox());
          focus.dispose();
          semantics.dispose();
        }
      });
      testWidgets(
        '$suite $kind live disable and owner replacement reject stale actions',
        (t) async {
          final semantics = t.ensureSemantics();
          final focus = FocusNode();
          try {
            final a = <InteractionSource>[], b = <InteractionSource>[];
            var owner = a, enabled = true, label = '原操作';
            late StateSetter update;
            await t.pumpWidget(
              host(
                StatefulBuilder(
                  builder: (c, s) {
                    update = s;
                    final binding = owner;
                    return StarBridgeActionButton(
                      kind: kind,
                      controlKey: const Key('target'),
                      focusNode: focus,
                      onActivate: enabled ? binding.add : null,
                      child: Text(label),
                    );
                  },
                ),
                suite,
                SplashProbe(),
              ),
            );
            await t.pump();
            final old = t.getSemantics(find.byKey(const Key('target'))).id;
            final gesture = await t.startGesture(
              t.getCenter(find.byKey(const Key('target'))),
            );
            await t.pump();
            update(() => enabled = false);
            await t.pump();
            await gesture.up();
            await t.pump();
            t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
              old,
              ui.SemanticsAction.tap,
            );
            await t.pump();
            expect(a, isEmpty);
            update(() {
              owner = b;
              enabled = true;
              label = '新操作';
            });
            await t.pump();
            expect(exposedButtons(t).single.getSemanticsData().label, '新操作');
            readerTap(t, find.byKey(const Key('target')));
            await t.pump();
            expect(a, isEmpty);
            expect(b, [InteractionSource.keyboard]);
            final latest = t.getSemantics(find.byKey(const Key('target'))).id;
            await t.pumpWidget(host(const Text('已离开'), suite, SplashProbe()));
            await t.pump();
            t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
              latest,
              ui.SemanticsAction.tap,
            );
            await t.pump();
            expect(b, [InteractionSource.keyboard]);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            focus.dispose();
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite reader source remains instant in asynchronous command context',
      (t) async {
        final semantics = t.ensureSemantics();
        try {
          final sources = <InteractionSource>[];
          await t.pumpWidget(
            host(
              StarBridgeActionButton(
                controlKey: const Key('target'),
                onActivate: (_) async {
                  sources.add(currentStarBridgeActivationSource);
                  await Future<void>.delayed(const Duration(milliseconds: 1));
                  sources.add(currentStarBridgeActivationSource);
                },
                child: const Text('打开'),
              ),
              suite,
              SplashProbe(),
            ),
          );
          await t.pump();
          readerTap(t, find.byKey(const Key('target')));
          await t.pump(const Duration(milliseconds: 1));
          expect(sources, [
            InteractionSource.keyboard,
            InteractionSource.keyboard,
          ]);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
