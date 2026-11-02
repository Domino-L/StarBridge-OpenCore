import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_tooltip.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_gameplay_tags.dart';
import 'package:starbridge_flutter/features/communities/legacy_community_tag_catalog.dart';
import 'package:starbridge_flutter/shared/ships/ship_classification_tag.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3b_test.dart' show exposedNodes;
import 'interaction_batch3i_test.dart' show scopedApp;

const shipLabel = '轻型地面运输载具类型完整说明';
const unknownTag = '自定义未知玩法标签原样保留';
const tagColor = Color(0xff75c9d6);
const fittingNames = ['探索', '战斗', '社交', '休闲', '新手友好', '运输'];

String tagHint(String kind) => switch (kind) {
  'ship' => shipLabel,
  'unknown' => unknownTag,
  'overflow' => '自定义未知 · 战斗 · PVE',
  _ =>
    '玩法主轴 · 探索\n${LegacyCommunityTagCatalog.tags.singleWhere((t) => t.id == 'core_exploration').description}',
};

class TagsProbe {
  TagsProbe(this.suite, this.kind);
  InteractionSuite suite;
  final String kind;
  bool reduce = false, light = false;
  int escaped = 0, actions = 0;
  final before = FocusNode(), after = FocusNode();
  late StateSetter update;
  Widget app() => StatefulBuilder(
    builder: (_, state) {
      update = state;
      return scopedApp(
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () => escaped++,
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                focusNode: before,
                onPressed: () => actions++,
                child: const Text('Before tags'),
              ),
              SizedBox(
                key: const Key('passive-tag-bounds'),
                width: 110,
                child: switch (kind) {
                  'ship' => const ShipClassificationTag(
                    label: shipLabel,
                    color: tagColor,
                  ),
                  'unknown' => const CommunityGameplayTags(
                    value: unknownTag,
                    maxTagWidth: 110,
                  ),
                  'overflow' => const CommunityGameplayTags(
                    value: '探索 · 自定义未知 · 战斗 · PVE',
                    maxVisible: 1,
                  ),
                  _ => const CommunityGameplayTags(
                    value: 'core_exploration',
                    maxTagWidth: 110,
                  ),
                },
              ),
              TextButton(
                focusNode: after,
                onPressed: () => actions++,
                child: const Text('After tags'),
              ),
            ],
          ),
        ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    before.dispose();
    after.dispose();
  }
}

Finder tagTooltip(String message) => find.byWidgetPredicate(
  (w) => w is StarBridgeTooltip && w.message == message,
);

SuiteTooltipState tagHintState(WidgetTester t, String message) => t.state(
  find.descendant(of: tagTooltip(message), matching: find.byType(SuiteTooltip)),
);

Future<void> tagsFrames(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

void expectPassiveTagSemantics(WidgetTester t, String message) {
  final nodes = exposedNodes(t);
  final messages = t
      .widgetList<StarBridgeTooltip>(find.byType(StarBridgeTooltip))
      .map((hint) => hint.message)
      .toList();
  expect(messages, contains(message));
  final details = nodes
      .map((node) {
        final d = node.getSemanticsData();
        return 'node ${node.id}: label=${d.label}; hint=${d.hint}; '
            'tooltip=${d.tooltip}; button=${d.flagsCollection.isButton}; '
            'tap=${d.hasAction(ui.SemanticsAction.tap)}; '
            'longPress=${d.hasAction(ui.SemanticsAction.longPress)}; '
            'custom=${d.customSemanticsActionIds}';
      })
      .join('\n');
  for (final expected in messages) {
    final pattern = RegExp(RegExp.escape(expected));
    final carriers = nodes
        .map((node) {
          final d = node.getSemanticsData();
          // A native text label and its tooltip may name the same passive node.
          // Count that exposed node once, but reject repetitions within a field
          // and duplicate carriers. No whole-Wrap assumption: every complete
          // sibling hint, including +N's hidden names, must remain exposed.
          final count = [d.label, d.hint, d.tooltip]
              .map((field) => pattern.allMatches(field).length)
              .reduce((a, b) => a > b ? a : b);
          return (node, count);
        })
        .where((entry) => entry.$2 > 0)
        .toList();
    expect(
      carriers,
      hasLength(1),
      reason:
          'Exactly one exposed carrier for FULL hint "$expected".\n$details',
    );
    expect(
      carriers.single.$2,
      1,
      reason:
          'The same complete hint may not repeat within a semantic field.\n$details',
    );
    final d = carriers.single.$1.getSemanticsData();
    expect(d.flagsCollection.isButton, isFalse, reason: details);
    expect(d.hasAction(ui.SemanticsAction.tap), isFalse, reason: details);
    expect(d.hasAction(ui.SemanticsAction.longPress), isFalse, reason: details);
    expect(d.customSemanticsActionIds ?? [], isEmpty, reason: details);
  }
}

Future<void> tabToTagButton(WidgetTester t, TagsProbe p, FocusNode node) async {
  for (var i = 0; !node.hasPrimaryFocus && i < 15; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await tagsFrames(t);
  }
  expect(
    node.hasPrimaryFocus,
    isTrue,
    reason: '$node\n${FocusManager.instance.toStringDeep()}',
  );
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final kind in ['ship', 'known', 'unknown', 'overflow']) {
      for (final input in ['hover', 'touch']) {
        testWidgets(
          '3fo $suite $kind $input full passive hint and live static settings',
          (t) async {
            size(t, const Size(1000, 800));
            final semantics = t.ensureSemantics();
            final p = TagsProbe(suite, kind);
            TestGesture? mouse;
            try {
              await t.pumpWidget(p.app());
              await tagsFrames(t);
              final message = tagHint(kind);
              final target = tagTooltip(message);
              expect(target, findsOneWidget);
              final adapter = t.widget<StarBridgeTooltip>(target);
              expect(adapter.consumeEscape, isFalse);
              expect(adapter.excludeFromSemantics, isFalse);
              final rect = t.getRect(
                find.byKey(const Key('passive-tag-bounds')),
              );
              expectPassiveTagSemantics(t, message);
              if (input == 'hover') {
                mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
                await mouse.addPointer(location: const Offset(1, 1));
                await mouse.moveTo(t.getCenter(target));
                await t.pump(const Duration(milliseconds: 500));
              } else {
                final touch = await t.startGesture(
                  t.getCenter(target),
                  kind: ui.PointerDeviceKind.touch,
                );
                await t.pump(const Duration(milliseconds: 600));
                await touch.up();
              }
              await t.pump(const Duration(milliseconds: 200));
              expect(tagHintState(t, message).isShowing, isTrue);
              expect(
                t.getRect(find.byKey(const Key('passive-tag-bounds'))),
                rect,
              );
              expectPassiveTagSemantics(t, message);
              expect(p.actions, 0);
              p.update(() {
                p.reduce = true;
                p.light = true;
              });
              await tagsFrames(t);
              expect(tagHintState(t, message).isShowing, isTrue);
              final opacities = t
                  .widgetList<Opacity>(
                    find.descendant(of: target, matching: find.byType(Opacity)),
                  )
                  .toList();
              expect(opacities, hasLength(1));
              expect(opacities.single.opacity, 1);
              expect(
                t.getRect(find.byKey(const Key('passive-tag-bounds'))),
                rect,
              );
              expect(p.actions, 0);
              expect(t.takeException(), isNull);
            } finally {
              await mouse?.removePointer();
              await p.close(t);
              semantics.dispose();
            }
          },
        );
      }
    }

    testWidgets(
      '3fo $suite passive labels skip real Tab and same Escape reaches owner',
      (t) async {
        size(t, const Size(1000, 800));
        final semantics = t.ensureSemantics();
        final p = TagsProbe(suite, 'overflow');
        final mouse = await t.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await t.pumpWidget(p.app());
          await tagsFrames(t);
          await tabToTagButton(t, p, p.before);
          await t.sendKeyEvent(LogicalKeyboardKey.tab);
          await tagsFrames(t);
          expect(
            p.after.hasPrimaryFocus,
            isTrue,
            reason:
                'Passive tooltip may not invent an intermediate focus target',
          );
          expect(tagHintState(t, tagHint('overflow')).isShowing, isFalse);
          expect(p.actions, 0);
          await mouse.addPointer(location: const Offset(1, 1));
          await mouse.moveTo(t.getCenter(tagTooltip(tagHint('overflow'))));
          await t.pump(const Duration(milliseconds: 500));
          await t.pump(const Duration(milliseconds: 200));
          expect(tagHintState(t, tagHint('overflow')).isShowing, isTrue);
          expect(
            p.after.hasPrimaryFocus,
            isTrue,
            reason: 'Hover never steals keyboard focus',
          );
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await tagsFrames(t);
          expect(p.escaped, 1);
          expect(tagHintState(t, tagHint('overflow')).isShowing, isFalse);
          expect(p.after.hasPrimaryFocus, isTrue);
          expect(p.actions, 0);
          expect(t.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await p.close(t);
          semantics.dispose();
        }
      },
    );

    for (final light in [false, true]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
          '3fo $suite light=$light scale=$scale fitted and overflow retain geometry',
          (t) async {
            size(t, const Size(1400, 900));
            for (final height in [32.0, 64.0]) {
              for (final width in [190.0, 320.0, 560.0]) {
                await t.pumpWidget(
                  scopedApp(
                    Builder(
                      builder: (context) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: TextScaler.linear(scale)),
                        child: SizedBox(
                          width: width * scale,
                          height: height * scale,
                          child: const CommunityGameplayTags(
                            value: '探索 · 战斗 · 社交 · 休闲 · 新手友好 · 运输',
                            fitAvailableSpace: true,
                          ),
                        ),
                      ),
                    ),
                    suite,
                    light: light,
                  ),
                );
                await tagsFrames(t);
                final bounds = t.getRect(find.byType(CommunityGameplayTags));
                final visible = <String>[];
                for (final name in fittingNames) {
                  final target = find.byKey(
                    ValueKey('community-gameplay-tag-$name'),
                  );
                  if (target.evaluate().isEmpty) continue;
                  visible.add(name);
                  final rect = t.getRect(target);
                  expect(rect.right, lessThanOrEqualTo(bounds.right + .01));
                  expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + .01));
                }
                final hidden = fittingNames
                    .where((n) => !visible.contains(n))
                    .toList();
                if (hidden.isNotEmpty) {
                  expect(find.text('+${hidden.length}'), findsOneWidget);
                  final summary = tagTooltip(hidden.join(' · '));
                  expect(summary, findsOneWidget);
                  expect(
                    t.widget<StarBridgeTooltip>(summary).consumeEscape,
                    isFalse,
                  );
                  final more = t.getRect(find.text('+${hidden.length}'));
                  expect(more.right, lessThanOrEqualTo(bounds.right + .01));
                  expect(more.bottom, lessThanOrEqualTo(bounds.bottom + .01));
                }
                if (width == 560 || (width == 320 && height == 64)) {
                  expect(visible, fittingNames);
                  expect(find.textContaining(RegExp(r'^\+\d+$')), findsNothing);
                }
                expect(t.takeException(), isNull);
              }
            }
            // Original long-label fitting is not allowed to regress to an
            // arbitrary one-third allocation after the wrapper replacement.
            await t.pumpWidget(
              scopedApp(
                const SizedBox(
                  width: 440,
                  height: 32,
                  child: CommunityGameplayTags(
                    value: 'Weekend Exploration Crew · PVE',
                    fitAvailableSpace: true,
                  ),
                ),
                suite,
                light: light,
              ),
            );
            await tagsFrames(t);
            expect(
              t
                  .renderObject<RenderParagraph>(
                    find.text('Weekend Exploration Crew'),
                  )
                  .didExceedMaxLines,
              isFalse,
            );
            expect(find.text('PVE'), findsOneWidget);
            await t.pumpWidget(const SizedBox());
          },
        );
      }
    }

    testWidgets(
      '3fo $suite original colors padding end fade and unknown text survive',
      (t) async {
        size(t, const Size(1000, 800));
        await t.pumpWidget(
          scopedApp(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(
                  width: 110,
                  child: ShipClassificationTag(
                    label: shipLabel,
                    color: tagColor,
                  ),
                ),
                CommunityGameplayTags(
                  value: '探索 / core_exploration · 自定义未知 · 自定义未知 · 未公开',
                  maxTagWidth: 110,
                ),
              ],
            ),
            suite,
          ),
        );
        await tagsFrames(t);
        final ship = find.byType(ShipClassificationTag);
        final shipContainer = t.widget<Container>(
          find.descendant(of: ship, matching: find.byType(Container)),
        );
        expect(
          shipContainer.padding,
          const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        );
        final shipDecoration = shipContainer.decoration! as BoxDecoration;
        expect(shipDecoration.color, tagColor.withValues(alpha: .06));
        expect(
          shipDecoration.border,
          Border.all(color: tagColor.withValues(alpha: .6)),
        );
        expect(shipDecoration.borderRadius, BorderRadius.circular(2));
        expect(
          t.widget<Text>(find.text(shipLabel)).overflow,
          TextOverflow.fade,
        );
        expect(
          t
              .renderObject<RenderParagraph>(find.text(shipLabel))
              .debugHasOverflowShader,
          isTrue,
        );
        expect(
          communityTagNames('探索 / core_exploration · 自定义未知 · 自定义未知 · 未公开'),
          ['探索', 'core_exploration', '自定义未知'],
        );
        expect(
          find.text('探索'),
          findsNWidgets(2),
          reason: 'Raw id/name alias entries are not rewritten or deduplicated by presentation',
        );
        expect(find.text('自定义未知'), findsOneWidget);
        expect(find.text('未公开'), findsNothing);
        final unknown = find.byKey(
          const ValueKey('community-gameplay-tag-自定义未知'),
        );
        final container = t.widget<Container>(unknown);
        final context = t.element(unknown);
        final accent = context.tokens.colors.textSecondary;
        expect(
          container.padding,
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        );
        expect(container.constraints!.maxWidth, 110);
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, accent.withValues(alpha: .14));
        expect(
          decoration.border,
          Border.all(color: accent.withValues(alpha: .68)),
        );
        expect(decoration.borderRadius, BorderRadius.circular(4));
        expect(
          t.widget<Text>(find.text('自定义未知')).style!.fontWeight,
          FontWeight.w600,
        );
        expect(t.widget<Text>(find.text('自定义未知')).maxLines, 1);
        expect(
          t.widget<StarBridgeTooltip>(tagTooltip('自定义未知')).message,
          '自定义未知',
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
