import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/shell/chrome/shell_chrome_projection.dart';
import 'package:starbridge_flutter/app/shell/shell_layout_mode.dart';
import 'package:starbridge_flutter/app/shell/widgets/attention_badge.dart';
import 'package:starbridge_flutter/app/shell/widgets/top_bar_actions.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_native_icon_action.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3i_test.dart' show scopedApp;

const topProjection = ShellChromeProjection(
  overlay: OverlaySceneProjection(
    options: [],
    preferredSceneId: null,
    actualSceneId: null,
    canChange: false,
  ),
  accountLabel: 'Test Pilot',
  presenceKey: 'presence.offline',
  syncKey: 'sync.idle',
  friendAttentionCount: 0,
  notificationCount: 0,
);
const topIds = ['friends', 'notifications', 'settings'];

class TopProbe {
  TopProbe(this.suite);
  final InteractionSuite suite;
  final liveCount = ValueNotifier(0);
  ShellChromeProjection projection = topProjection;
  bool reduce = false, light = false, reference = false, shown = true;
  double scale = 1;
  final selected = <FeatureDescriptor>[];
  final sources = <InteractionSource>[];
  final prepared = <String>[];
  final gates = <Completer<void>>[];
  int accountCalls = 0, destinationsBuilt = 0;
  late StateSetter update;
  late final descriptors = [
    for (var i = 0; i < topIds.length; i++)
      FeatureDescriptor(
        id: topIds[i],
        route: '/fixture/${topIds[i]}',
        labelKey: 'navigation.${topIds[i]}',
        descriptionKey: 'navigation.${topIds[i]}',
        icon: [
          StarBridgeIconSemantic.friends,
          StarBridgeIconSemantic.notifications,
          StarBridgeIconSemantic.settings,
        ][i],
        navigationRegion: NavigationRegion.topBar,
        order: i,
        attentionCount: i == 0 ? liveCount : null,
        prefetch: () {
          prepared.add(topIds[i]);
          final gate = Completer<void>();
          gates.add(gate);
          return gate.future;
        },
        buildDestination: (_) {
          destinationsBuilt++;
          return const SizedBox();
        },
      ),
  ];
  Widget app() => StatefulBuilder(
    builder: (_, state) {
      update = state;
      return scopedApp(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: Semantics(
              explicitChildNodes: true,
              child: shown
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TopBarActions(
                          descriptors: descriptors,
                          accountMenuDestinations: const [],
                          projection: projection,
                          mode: ShellLayoutMode.wide,
                          onSelect: (descriptor) {
                            selected.add(descriptor);
                            sources.add(currentStarBridgeActivationSource);
                          },
                          onAccountLogin: () => accountCalls++,
                          onAccountLogout: () => accountCalls++,
                          onAccountIssueAction: () => accountCalls++,
                        ),
                        if (reference) ...[
                          const SizedBox(height: 30),
                          ValueListenableBuilder<int>(
                            valueListenable: liveCount,
                            builder: (context, count, _) => nativeReference(
                              context,
                              descriptors,
                              [count, projection.notificationCount, 0],
                            ),
                          ),
                        ],
                      ],
                    )
                  : const Text('Top actions left'),
            ),
          ),
        ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
  void finish() {
    for (final gate in gates) {
      if (!gate.isCompleted) gate.complete();
    }
    liveCount.dispose();
  }
}

// Original TopIconButton style, retained as the native visual/geometry control.
ButtonStyle referenceStyle(BuildContext context, int position, int total) {
  final tokens = context.tokens;
  return ButtonStyle(
    minimumSize: WidgetStatePropertyAll(
      Size.square(tokens.density.controlHeight - tokens.stroke.strong * 2),
    ),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: tokens.shape.small),
    ),
    side: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.focused)
          ? BorderSide(
              color: tokens.colors.focusRing,
              width: tokens.stroke.focusWidth,
            )
          : BorderSide.none,
    ),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)
          ? tokens.surfaces.selected.fill
          : Colors.transparent,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)
          ? tokens.colors.accent
          : tokens.colors.textSecondary,
    ),
    overlayColor: WidgetStatePropertyAll(
      tokens.colors.accent.withValues(alpha: .10),
    ),
  );
}

Widget nativeReference(
  BuildContext context,
  List<FeatureDescriptor> descriptors,
  List<int> counts,
) {
  final tokens = context.tokens;
  // QualityPass ⑦ A (user 2026-10-29): plain icons, no boxed group.
  return SizedBox(
    key: const Key('reference-cluster'),
    height: tokens.density.controlHeight,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < descriptors.length; i++) ...[
          if (i > 0) SizedBox(width: tokens.space.xxs),
          IconButton(
            key: Key('reference-${descriptors[i].id}'),
            onPressed: () {},
            tooltip: AppStrings.of(context).text(descriptors[i].labelKey),
            style: referenceStyle(context, i, descriptors.length),
            icon: AttentionBadge(
              count: counts[i],
              child: StarBridgeIcon(
                descriptors[i].icon,
                size: tokens.icons.medium,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

Finder topButton(String id) => find.byKey(ValueKey('top-action-$id'));
StarBridgeNativeIconAction topAdapter(WidgetTester t, String id) =>
    t.widget<StarBridgeNativeIconAction>(
      find.ancestor(
        of: topButton(id),
        matching: find.byType(StarBridgeNativeIconAction),
      ),
    );
String topLabel(WidgetTester t, String id) => topAdapter(t, id).label;

Future<void> topFrames(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

Future<void> topActivate(
  WidgetTester t,
  Finder target,
  String label,
  String input,
) async {
  expect(target, findsOneWidget);
  if (input == 'reader') {
    final nodes = exposedNodes(t).where((n) {
      final d = n.getSemanticsData();
      return d.label == label && d.hasAction(ui.SemanticsAction.tap);
    }).toList();
    expect(nodes, hasLength(1));
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      ui.SemanticsAction.tap,
    );
  } else if (input == 'keyboard') {
    final node = t.widget<IconButton>(target).focusNode!;
    FocusScope.of(t.element(target)).unfocus();
    await topFrames(t);
    for (var i = 0; !node.hasPrimaryFocus && i < 30; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await topFrames(t);
    }
    expect(
      node.hasPrimaryFocus,
      isTrue,
      reason: '$node\n${FocusManager.instance.toStringDeep()}',
    );
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final pointer = await t.startGesture(
      t.getCenter(target),
      kind: ui.PointerDeviceKind.touch,
    );
    await pointer.up();
  }
  await topFrames(t);
}

void expectTopSemantics(WidgetTester t, String id, int count) {
  final label = topLabel(t, id);
  final expected = count > 0 ? '$label\n$count' : label;
  final nodes = exposedNodes(t)
      .where(
        (n) =>
            n.getSemanticsData().label == expected &&
            n.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      )
      .toList();
  expect(nodes, hasLength(1));
  final hints = find.descendant(
    of: find.ancestor(
      of: topButton(id),
      matching: find.byType(StarBridgeNativeIconAction),
    ),
    matching: find.byType(StarBridgeTooltip),
  );
  expect(t.widget<StarBridgeTooltip>(hints).message, label);
  expect(t.widget<StarBridgeTooltip>(hints).excludeFromSemantics, isTrue);
  final countWidget = find.descendant(
    of: topButton(id),
    matching: find.byType(AttentionCount),
  );
  if (count > 0) {
    expect(t.widget<AttentionCount>(countWidget).count, count);
    expect(
      find.descendant(
        of: countWidget,
        matching: find.text(count > 99 ? '99+' : '$count'),
      ),
      findsOneWidget,
    );
  } else {
    expect(countWidget, findsNothing);
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['touch', 'keyboard', 'reader']) {
      testWidgets(
        '3fk $suite $input top callbacks retain actual count and immediate repeat',
        (t) async {
          size(t, const Size(1400, 1000));
          final semantics = t.ensureSemantics();
          final p = TopProbe(suite);
          try {
            await t.pumpWidget(p.app());
            await t.pump(const Duration(milliseconds: 100));
            await t.pump();
            expect(p.prepared, isEmpty);
            expect(p.destinationsBuilt, 0);
            for (final count in [0, 99, 125]) {
              p.liveCount.value = count;
              p.update(
                () => p.projection = p.projection.copyWith(
                  friendAttentionCount: 666,
                  notificationCount: count,
                ),
              );
              await topFrames(t);
              expectTopSemantics(t, 'friends', count);
              expectTopSemantics(t, 'notifications', count);
              expectTopSemantics(t, 'settings', 0);
              for (final id in topIds) {
                final before = p.selected.length;
                await topActivate(
                  t,
                  topButton(id),
                  topAdapter(t, id).semanticLabel!,
                  input,
                );
                expect(p.selected, hasLength(before + 1));
                expect(
                  identical(p.selected.last, p.descriptors[topIds.indexOf(id)]),
                  isTrue,
                );
                expect(
                  p.sources.last,
                  input == 'touch'
                      ? InteractionSource.pointer
                      : InteractionSource.keyboard,
                );
              }
            }
            p.update(() {
              p.reduce = true;
              p.light = true;
            });
            await topFrames(t);
            for (var i = 0; i < 4; i++) {
              final count = p.selected.length;
              await topActivate(
                t,
                topButton('friends'),
                topAdapter(t, 'friends').semanticLabel!,
                input,
              );
              expect(
                p.selected,
                hasLength(count + 1),
                reason: 'no active-input throttle or duplicate callback',
              );
            }
            expect(p.accountCalls, 0);
            expect(p.destinationsBuilt, 0);
            expect(p.liveCount.value, 125);
            expect(
              p.projection.friendAttentionCount,
              666,
              reason: 'presentation does not mutate the projection owner',
            );
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            p.finish();
            semantics.dispose();
          }
        },
      );
    }

    for (final light in [false, true]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
          '3fk $suite light=$light text=$scale matches original native style and geometry',
          (t) async {
            size(t, const Size(1800, 1000));
            final p = TopProbe(suite)
              ..reference = true
              ..light = light
              ..scale = scale;
            try {
              await t.pumpWidget(p.app());
              await t.pump(const Duration(milliseconds: 100));
              await t.pump();
              for (final count in [0, 99, 125]) {
                p.liveCount.value = count;
                p.update(
                  () => p.projection = p.projection.copyWith(
                    notificationCount: count,
                  ),
                );
                await topFrames(t);
                final cluster = find.byKey(const Key('top-action-cluster'));
                expect(
                  t.getSize(cluster),
                  t.getSize(find.byKey(const Key('reference-cluster'))),
                );
                for (final id in topIds) {
                  final reference = find.byKey(Key('reference-$id'));
                  expect(t.getSize(topButton(id)), t.getSize(reference));
                  final actual = t.widget<IconButton>(topButton(id));
                  final original = t.widget<IconButton>(reference);
                  expect(actual.iconSize, original.iconSize);
                  final face = topAdapter(t, id).style;
                  for (final states in [
                    <WidgetState>{},
                    {WidgetState.hovered},
                    {WidgetState.focused},
                    {WidgetState.pressed},
                  ]) {
                    expect(
                      face.minimumSize?.resolve(states),
                      original.style!.minimumSize?.resolve(states),
                    );
                    expect(
                      face.shape?.resolve(states),
                      original.style!.shape?.resolve(states),
                    );
                    expect(
                      face.side?.resolve(states),
                      original.style!.side?.resolve(states),
                    );
                    expect(
                      face.backgroundColor?.resolve(states),
                      original.style!.backgroundColor?.resolve(states),
                    );
                    expect(
                      face.foregroundColor?.resolve(states),
                      original.style!.foregroundColor?.resolve(states),
                    );
                    expect(
                      face.overlayColor?.resolve(states),
                      original.style!.overlayColor?.resolve(states),
                    );
                  }
                }
              }
              expect(p.selected, isEmpty);
              expect(p.prepared, isEmpty);
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox());
              p.finish();
            }
          },
        );
      }
    }

    testWidgets(
      '3fk $suite prefetch stays optional, delayed and independent from navigation',
      (t) async {
        size(t, const Size(1400, 1000));
        final p = TopProbe(suite);
        final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await t.pumpWidget(p.app());
          await t.pump(const Duration(milliseconds: 100));
          await t.pump();
          expect(p.prepared, isEmpty);
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(t.getCenter(topButton('friends')));
          await t.pump(const Duration(milliseconds: 200));
          await mouse.moveTo(Offset.zero);
          await t.pump(const Duration(milliseconds: 400));
          expect(p.prepared, isEmpty);
          await mouse.moveTo(t.getCenter(topButton('friends')));
          await t.pump(const Duration(milliseconds: 350));
          expect(p.prepared, ['friends']);
          expect(p.selected, isEmpty);
          expect(p.destinationsBuilt, 0);
          await topActivate(
            t,
            topButton('friends'),
            topAdapter(t, 'friends').semanticLabel!,
            'touch',
          );
          expect(p.selected, [
            p.descriptors.first,
          ], reason: 'held prefetch never owns activation admission');
          expect(p.gates.single.isCompleted, isFalse);
          p.liveCount.value = 125;
          p.update(() => p.light = true);
          await t.pump(const Duration(seconds: 1));
          expect(p.prepared, [
            'friends',
          ], reason: 'remaining hover/focus is not polling');
          p.gates.single.completeError(
            StateError('optional warming unavailable'),
          );
          await topFrames(t);
          expect(t.takeException(), isNull);
          final lastPrepared = p.prepared.length;
          await mouse.moveTo(t.getCenter(topButton('notifications')));
          await t.pump(const Duration(milliseconds: 100));
          p.update(() => p.shown = false);
          await t.pump();
          await t.pump(const Duration(seconds: 1));
          expect(
            p.prepared,
            hasLength(lastPrepared),
            reason: 'unmount cancels only pending intent prefetch',
          );
        } finally {
          await mouse.removePointer();
          await t.pumpWidget(const SizedBox());
          p.finish();
        }
      },
    );

    testWidgets(
      '3fk $suite NativeIconAction semantic override is optional and disabled-safe',
      (t) async {
        size(t, const Size(1000, 800));
        final semantics = t.ensureSemantics();
        var override = false, enabled = true, calls = 0;
        late StateSetter update;
        try {
          await t.pumpWidget(
            StatefulBuilder(
              builder: (_, state) {
                update = state;
                return scopedApp(
                  StarBridgeNativeIconAction(
                    controlKey: const Key('default-native-icon'),
                    label: 'Original tooltip',
                    semanticLabel: override ? 'Reader count\n175' : null,
                    icon: const Icon(Icons.star),
                    onActivate: enabled ? (_) => calls++ : null,
                  ),
                  suite,
                );
              },
            ),
          );
          await t.pump(const Duration(milliseconds: 100));
          await t.pump();
          expect(
            exposedNodes(t).where(
              (n) =>
                  n.getSemanticsData().label == 'Original tooltip' &&
                  n.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            ),
            hasLength(1),
          );
          update(() => override = true);
          await topFrames(t);
          expect(
            t.widget<StarBridgeTooltip>(find.byType(StarBridgeTooltip)).message,
            'Original tooltip',
          );
          await topActivate(
            t,
            find.byKey(const Key('default-native-icon')),
            'Reader count\n175',
            'reader',
          );
          expect(calls, 1);
          update(() => enabled = false);
          await topFrames(t);
          final node = exposedNodes(t)
              .where((n) => n.getSemanticsData().label == 'Reader count\n175')
              .single;
          expect(
            node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            isFalse,
          );
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        }
      },
    );
  }
}
