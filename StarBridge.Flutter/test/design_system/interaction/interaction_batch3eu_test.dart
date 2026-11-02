import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_choice_chip.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_removable_chip_group.dart';
import 'package:starbridge_flutter/features/party_rooms/room_tag_catalog.dart';
import 'package:starbridge_flutter/features/party_rooms/room_tag_colors.dart';
import 'package:starbridge_flutter/features/party_rooms/room_tag_picker.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3eo_test.dart' show key;
import 'interaction_batch3et_test.dart'
    show activate, openRoomForm, RoomFormPort, formData, chooseTags;
import 'interaction_batch3i_test.dart' show scopedApp;

class TagsProbe {
  TagsProbe(Iterable<String> initial, {this.filter = false})
    : value = Set.unmodifiable(initial);
  final bool filter;
  Set<String> value;
  int confirmations = 0;
  final returns = <Set<String>?>[];
  late StateSetter update;
  bool reduce = false, light = false;
  late InteractionSuite suite;
  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return scopedApp(
        Builder(
          builder: (context) => StarBridgeActionButton(
            controlKey: const Key('open-room-tags'),
            onActivate: (source) async {
              final next = await showRoomTagPicker(
                context,
                options: RoomTagCatalog.exampleOptions,
                selected: value,
                filter: filter,
                source: source,
              );
              returns.add(next);
              if (next != null) {
                confirmations++;
                value = next;
              }
            },
            child: const Text('Open tags'),
          ),
        ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

Future<TagsProbe> picker(
  WidgetTester t,
  InteractionSuite suite, {
  Iterable<String> initial = const ['combat'],
  bool filter = false,
}) async {
  size(t, const Size(1300, 1100));
  final probe = TagsProbe(initial, filter: filter)..suite = suite;
  await t.pumpWidget(probe.app());
  await t.pumpAndSettle();
  await activate(t, key('open-room-tags'), 'pointer');
  await t.pumpAndSettle();
  return probe;
}

Set<String> shown(WidgetTester t) => t
    .widget<StarBridgeRemovableChipGroup>(
      find.byType(StarBridgeRemovableChipGroup),
    )
    .chips
    .map((c) => c.id.substring('selected-tag-'.length))
    .toSet();

Future<void> selectTag(WidgetTester t, String id, String source) async {
  final tag = RoomTagCatalog.exampleOptions.firstWhere((tag) => tag.id == id);
  await t.enterText(key('tag-catalog-search'), RoomTagCatalog.fullText(tag));
  await t.pumpAndSettle();
  await activate(t, key('search-tag-$id'), source);
  await t.pump();
}

Future<void> removeTag(WidgetTester t, String id, String source) async {
  final presentationId = 'selected-tag-$id';
  final data = InteractionScope.of(
    t.element(find.byType(StarBridgeRemovableChipGroup)),
  );
  if (source == 'keyboard') {
    for (
      var step = 0;
      FocusManager.instance.primaryFocus?.debugLabel !=
              'remove-$presentationId' &&
          step < 128;
      step++
    ) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'remove-$presentationId',
    );
    await t.sendKeyEvent(LogicalKeyboardKey.delete);
  } else if (data.suite == InteractionSuite.standard) {
    final target = find.byKey(ValueKey(presentationId));
    await t.ensureVisible(target);
    if (source == 'pointer') {
      await t.tap(
        find.descendant(of: target, matching: find.byType(Icon)).last,
      );
    } else {
      final delete = find.descendant(
        of: target,
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.onTap != null,
        ),
      );
      final node = t.getSemantics(delete.last);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
    }
  } else {
    await activate(
      t,
      find.byKey(ValueKey<Object>(('chip-remove', presentationId))),
      source,
    );
  }
  await t.pump();
}

Finder tagsCancel() => find.descendant(
  of: find.byType(AlertDialog).last,
  matching: find.byWidgetPredicate(
    (w) => w is StarBridgeActionButton && w.kind == StarBridgeActionKind.quiet,
  ),
);

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite tags $source replace branch, keep siblings, remove and explicitly confirm',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final probe = await picker(t, suite);
            expect(find.byType(StarBridgeFieldFrame), findsOneWidget);
            expect(shown(t), {'combat'});
            await selectTag(t, 'pve_bounty', source);
            expect(shown(t), {'pve_bounty'});
            await selectTag(t, 'pvp_fps', source);
            expect(shown(t), {'pve_bounty', 'pvp_fps'});
            expect(probe.value, {'combat'});
            await removeTag(t, 'pve_bounty', source);
            expect(shown(t), {'pvp_fps'});
            await activate(t, key('room-tags-confirm'), source);
            await t.pumpAndSettle();
            expect(probe.value, {'pvp_fps'});
            expect(probe.confirmations, 1);
            expect(find.byType(AlertDialog), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite tag browse rows and context chips keep the original limits',
      (t) async {
        final probe = await picker(t, suite, initial: const []);
        expect(find.byType(StarBridgeFieldFrame), findsOneWidget);
        await activate(t, key('room-tags-confirm'), 'pointer');
        await t.pumpAndSettle();
        expect(find.text('至少选择一条玩法路径。'), findsOneWidget);
        for (final id in ['combat', 'industry', 'support']) {
          await t.enterText(key('tag-catalog-search'), '');
          await t.pumpAndSettle();
          await activate(t, key('browse-tag-$id'), 'keyboard');
          await activate(t, key('room-tag-add-current'), 'keyboard');
          await t.pumpAndSettle();
        }
        expect(shown(t), {'combat', 'industry', 'support'});
        await selectTag(t, 'social', 'pointer');
        await t.pumpAndSettle();
        expect(shown(t), {'combat', 'industry', 'support'});
        expect(find.text('玩法路径最多选择 3 条。'), findsOneWidget);
        for (final id in ['need_pilot', 'need_gunner']) {
          await activate(t, key('context-tag-$id'), 'keyboard');
          await t.pumpAndSettle();
        }
        await activate(t, key('context-tag-pace_casual'), 'pointer');
        await t.pumpAndSettle();
        expect(shown(t), hasLength(5));
        expect(find.text('最多选择 5 个标签。'), findsOneWidget);
        expect(probe.confirmations, 0);
        await removeTag(t, 'support', 'keyboard');
        await activate(t, key('context-tag-pace_casual'), 'keyboard');
        final medic = key('context-tag-need_medic');
        await t.ensureVisible(medic);
        await t.pumpAndSettle();
        await t.tap(medic);
        await t.pumpAndSettle();
        expect(find.text('附加标签最多选择 3 个。'), findsOneWidget);
        expect(shown(t), {
          'combat',
          'industry',
          'need_pilot',
          'need_gunner',
          'pace_casual',
        });
        await activate(t, key('room-tags-confirm'), 'keyboard');
        await t.pumpAndSettle();
        expect(probe.value, {
          'combat',
          'industry',
          'need_pilot',
          'need_gunner',
          'pace_casual',
        });
      },
    );

    testWidgets(
      '$suite filter bypasses creation limits and cancellation cannot mutate the owner',
      (t) async {
        final probe = await picker(t, suite, filter: true);
        expect(find.byType(StarBridgeFieldFrame), findsOneWidget);
        for (final id in ['industry', 'support', 'social', 'arena']) {
          await selectTag(t, id, 'pointer');
          await t.pumpAndSettle();
        }
        for (final id in ['need_pilot', 'need_gunner', 'pace_casual']) {
          await activate(t, key('context-tag-$id'), 'pointer');
          await t.pumpAndSettle();
        }
        expect(shown(t), hasLength(8));
        final before = probe.value;
        await activate(t, tagsCancel(), 'keyboard');
        await t.pumpAndSettle();
        expect(probe.value, same(before));
        expect(probe.returns, [null]);
        await activate(t, key('open-room-tags'), 'keyboard');
        await t.pumpAndSettle();
        await removeTag(t, 'combat', 'keyboard');
        await activate(t, key('room-tags-confirm'), 'keyboard');
        await t.pumpAndSettle();
        expect(probe.value, isEmpty);
        expect(probe.confirmations, 1);
      },
    );

    testWidgets(
      '$suite tag search IME, branch selection and draft survive live settings',
      (t) async {
        final probe = await picker(t, suite);
        expect(find.byType(StarBridgeFieldFrame), findsOneWidget);
        await t.enterText(key('tag-catalog-search'), '赏金');
        final editor = t.state<EditableTextState>(find.byType(EditableText));
        editor.widget.controller.value = const TextEditingValue(
          text: '赏金',
          selection: TextSelection(baseOffset: 0, extentOffset: 2),
          composing: TextRange(start: 0, end: 2),
        );
        await t.pump();
        final value = editor.widget.controller.value;
        probe.update(() {
          probe.suite = InteractionSuite.glow;
          probe.reduce = true;
          probe.light = true;
        });
        await t.pump();
        await t.pump();
        expect(t.state(find.byType(EditableText)), same(editor));
        expect(editor.widget.controller.value, value);
        expect(shown(t), {'combat'});
        expect(key('search-tag-pve_bounty'), findsOneWidget);
        await activate(t, tagsCancel(), 'keyboard');
        await t.pumpAndSettle();
        expect(probe.value, {'combat'});
      },
    );

    testWidgets(
      '$suite quick remove and restore keeps one tag identity and fallback focus',
      (t) async {
        final probe = await picker(t, suite);
        expect(find.byType(StarBridgeFieldFrame), findsOneWidget);
        await removeTag(t, 'combat', 'pointer');
        await t.pump(const Duration(milliseconds: 20));
        if (suite != InteractionSuite.standard) {
          final transition = t.widget<SizeTransition>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('selected-tag-combat')),
                  matching: find.byType(SizeTransition),
                )
                .first,
          );
          expect(transition.sizeFactor.value, greaterThan(0));
          expect(transition.sizeFactor.value, lessThan(1));
        }
        await t.enterText(key('tag-catalog-search'), '战斗');
        await t.pump();
        await activate(t, key('search-tag-combat'), 'pointer');
        await t.pump();
        expect(shown(t), {'combat'});
        await t.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('selected-tag-combat')),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await removeTag(t, 'combat', 'keyboard');
        await t.pump();
        expect(shown(t), isEmpty);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'room-tag-search',
        );
        await activate(t, tagsCancel(), 'keyboard');
        await t.pumpAndSettle();
        expect(probe.value, {'combat'});
      },
    );

    testWidgets(
      '$suite actual create form receives removable tags without a business command',
      (t) async {
        final port = RoomFormPort()..result = await formData();
        final module = await openRoomForm(t, port, suite, 'create');
        try {
          await chooseTags(t);
          expect(shown(t), {'undecided'});
          await removeTag(t, 'undecided', 'keyboard');
          expect(shown(t), isEmpty);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'room-choose-tags',
          );
          expect(port.calls, 0);
          await activate(t, tagsCancel(), 'keyboard');
          await t.pumpAndSettle();
          expect(port.calls, 0);
        } finally {
          module.stopSession();
          await t.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets(
      '$suite selected tag labels and filter chips keep domain colours',
      (t) async {
        await picker(
          t,
          suite,
          initial: const ['combat', 'industry', 'support'],
        );
        final group = t.widget<StarBridgeRemovableChipGroup>(
          find.byType(StarBridgeRemovableChipGroup),
        );
        final context = t.element(find.byType(StarBridgeRemovableChipGroup));
        final original = InteractionScope.of(context).palette;
        for (final chip in group.chips) {
          final id = chip.id.substring('selected-tag-'.length);
          final expected = roomTagColors(context, id);
          expect(chip.foregroundColor, expected.foreground);
          expect(chip.backgroundColor, expected.soft);
          final target = find.byKey(ValueKey(chip.id));
          if (suite == InteractionSuite.standard) {
            expect(
              t.widget<InputChip>(target).labelStyle!.color,
              expected.foreground,
            );
          } else {
            final label = find.descendant(
              of: target,
              matching: find.text(chip.label),
            );
            expect(t.widget<Text>(label).style!.color, expected.foreground);
          }
        }
        final expected = roomTagColors(context, 'need_pilot');
        await activate(t, key('context-tag-need_pilot'), 'keyboard');
        await t.pumpAndSettle();
        if (suite == InteractionSuite.standard) {
          final chip = t.widget<FilterChip>(key('context-tag-need_pilot'));
          expect(chip.labelStyle!.color, expected.foreground);
          expect(chip.checkmarkColor, expected.foreground);
          expect(chip.selectedColor, expected.soft);
        } else {
          final palette = InteractionScope.of(
            t.element(key('context-tag-need_pilot')),
          ).palette;
          expect(palette.selectedFill, expected.soft);
          expect(palette.textPrimary, expected.foreground);
          expect(palette.textDisabled, original.textDisabled);
          expect(palette.focusRing, original.focusRing);
        }
        expect(InteractionScope.of(context).palette, same(original));
      },
    );

    testWidgets(
      '$suite optional chip colours cannot override disabled semantics or text',
      (t) async {
        await t.pumpWidget(
          scopedApp(
            const StarBridgeChoiceChip.filter(
              controlKey: Key('disabled-domain-chip'),
              label: 'Disabled domain',
              selected: true,
              foregroundColor: Colors.purple,
              selectedColor: Colors.amber,
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        if (suite == InteractionSuite.standard) {
          final chip = t.widget<FilterChip>(key('disabled-domain-chip'));
          expect(chip.onSelected, isNull);
          expect(chip.labelStyle, isNull);
        } else {
          final context = t.element(key('disabled-domain-chip'));
          final label = find.descendant(
            of: key('disabled-domain-chip'),
            matching: find.text('Disabled domain'),
          );
          expect(
            t.widget<Text>(label).style!.color,
            InteractionScope.of(context).palette.textDisabled,
          );
        }
      },
    );

    for (final confirmInput in ['keyboard', 'pointer']) {
      testWidgets(
        '$suite actual tag return uses final $confirmInput source, not opening source',
        (t) async {
          final port = RoomFormPort()..result = await formData();
          final module = await openRoomForm(t, port, suite, 'create');
          try {
            await activate(
              t,
              key('room-choose-tags'),
              confirmInput == 'pointer' ? 'keyboard' : 'pointer',
            );
            await t.pumpAndSettle();
            await selectTag(t, 'undecided', 'pointer');
            await activate(t, key('room-tags-confirm'), confirmInput);
            await t.pumpAndSettle();
            final group = t.widget<StarBridgeRemovableChipGroup>(
              find.byType(StarBridgeRemovableChipGroup),
            );
            expect(
              group.changeSource,
              confirmInput == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(shown(t), {'undecided'});
            expect(port.calls, 0);
          } finally {
            module.stopSession();
            await t.pumpWidget(const SizedBox());
          }
        },
      );
    }

    testWidgets(
      '$suite legacy alias remains owned by catalog normalization, not chip presentation',
      (t) async {
        final probe = await picker(t, suite, initial: const ['mixed_escort']);
        expect(shown(t), {'support_cargo_escort'});
        await removeTag(t, 'support_cargo_escort', 'keyboard');
        expect(shown(t), isEmpty);
        expect(probe.value, {'mixed_escort'});
        await selectTag(t, 'combat', 'pointer');
        await activate(t, key('room-tags-confirm'), 'keyboard');
        await t.pumpAndSettle();
        expect(probe.value, {'combat'});
      },
    );
  }
}
