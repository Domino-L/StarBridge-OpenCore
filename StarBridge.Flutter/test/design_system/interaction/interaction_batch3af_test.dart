import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_choice_chip.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_switch.dart';
import 'package:starbridge_flutter/features/communities/community_profile_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_profile_port.dart';

import 'interaction_batch3ae_test.dart' show mount, action;
import '../../features/communities/community_profile_dialog_test.dart'
    show EditorPort;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../../features/friends/social_layout_test.dart' show loadFonts;

class MotionPort extends EditorPort {
  final commands =
      <(String, String, Map<String, Object?>, InteractionSource)>[];
  Completer<CommunityProfileOutcome>? pending;
  int reads = 0;
  bool readFails = false;
  @override
  Future<CommunityEditingProfile> readProfile({
    String? targetRef,
    String? editRef,
  }) {
    reads++;
    if (readFails) return Future.error(StateError('read failed'));
    return super.readProfile(targetRef: targetRef, editRef: editRef);
  }

  @override
  Future<CommunityProfileOutcome> saveProfile(
    String request,
    String edit,
    Map<String, Object?> values,
  ) {
    commands.add((
      request,
      edit,
      Map.of(values),
      currentStarBridgeActivationSource,
    ));
    if (pending != null) return pending!.future;
    return super.saveProfile(request, edit, values);
  }
}

CommunityProfileDialog editor(MotionPort port) =>
    CommunityProfileDialog(port: port, targetRef: 'a' * 32, embedded: true);
CommunityProfileDialogState state(WidgetTester t) =>
    t.state<CommunityProfileDialogState>(find.byType(CommunityProfileDialog));
Finder input(String suffix) => find.byWidgetPredicate(
  (w) => w is TextFormField && w.key.toString().contains('-$suffix'),
);

Future<void> activate(WidgetTester t, Finder target, String source) async {
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'reader') {
    final semantics = find.descendant(
      of: target,
      matching: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.onTap != null,
      ),
    );
    final node = t.getSemantics(semantics.first);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  } else {
    final focus = find
        .descendant(of: target, matching: find.byType(Focus))
        .last;
    t.widget<Focus>(focus).focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  }
  await settleCommunityImages(t);
}

Finder toggle(String name) => find.byWidgetPredicate(
  (w) =>
      w is StarBridgeSwitch && w.controlKey == ValueKey('profile-toggle-$name'),
);
Finder chip(Key key) => find.byWidgetPredicate(
  (w) => w is StarBridgeChoiceChip && w.controlKey == key,
);
Finder nextDay(WidgetTester t) => find.byType(StarBridgeCheckboxTile);

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'profile active draft controls retain domain without autosave $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = MotionPort();
          addTearDown(port.changes.close);
          try {
            await mount(t, editor(port), suite);
            final owner = state(t);
            owner.update('activityWindows', [
              {
                'days': ['fri'],
                'startTime': '19:00',
                'endTime': '22:00',
                'endsNextDay': false,
              },
            ]);
            await settleCommunityImages(t);
            for (final name in [
              'publicListingEnabled',
              'publicShowDescription',
              'publicShowTags',
              'publicShowActiveSystems',
              'publicShowActivityTime',
              'emailNotificationsEnabled',
            ]) {
              final before = owner.fields[name];
              await activate(t, toggle(name), source);
              expect(owner.fields[name], before != true);
            }
            await activate(
              t,
              chip(const ValueKey('profile-language-日本語')),
              source,
            );
            expect(owner.fields['language'], 'English / 日本語');
            final serial = owner.serial;
            await activate(
              t,
              chip(ValueKey('profile-window-$serial-0-day-mon')),
              source,
            );
            expect(owner.rows('activityWindows').single['days'], [
              'fri',
              'mon',
            ]);
            await activate(t, nextDay(t), source);
            expect(owner.rows('activityWindows').single['endsNextDay'], true);
            await action(
              t,
              const ValueKey('community-system-stanton-control'),
              source,
            );
            expect(owner.fields['activeSystemIds'], ['pyro', 'stanton']);
            await action(t, const Key('profile-add-window'), source);
            expect(owner.rows('activityWindows'), hasLength(2));
            await action(
              t,
              ValueKey('profile-window-${owner.serial}-1-remove'),
              source,
            );
            expect(owner.rows('activityWindows'), hasLength(1));
            await action(t, const Key('profile-add-contact'), source);
            expect(owner.rows('externalContacts'), hasLength(2));
            await action(
              t,
              ValueKey('profile-contact-${owner.serial}-1-remove'),
              source,
            );
            expect(owner.rows('externalContacts'), hasLength(1));
            expect(owner, same(state(t)));
            await activate(t, toggle('recruitingEnabled'), source);
            expect(owner.fields['recruitingEnabled'], true);
            expect(owner.fields['publicListingEnabled'], true);
            expect(
              t
                  .widget<StarBridgeSwitch>(toggle('publicListingEnabled'))
                  .onChanged,
              isNull,
            );
            expect(port.commands, isEmpty);
            expect(port.saves, isEmpty);
            expect(owner.model.dirty, isTrue);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );

      testWidgets(
        'profile publication is separate explicit confirmation before save $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = MotionPort();
          (port.profile['profile'] as Map)['externalContacts'] = <Object?>[];
          addTearDown(port.changes.close);
          try {
            await mount(t, editor(port), suite);
            final owner = state(t);
            owner.update('externalContacts', [
              {'platform': 'Discord', 'value': 'new-private'},
            ]);
            await settleCommunityImages(t);
            await action(t, const Key('profile-save'), source);
            expect(port.commands, isEmpty);
            expect(owner.fields['publicShowExternalContacts'], false);
            final route =
                ModalRoute.of(t.element(find.byType(AlertDialog)))!
                    as StarBridgeDialogRoute;
            expect(route.instant, source != 'pointer');
            await action(t, const Key('profile-confirm-cancel'), source);
            expect(owner.model.dirty, isTrue);
            expect(owner.fields['publicShowExternalContacts'], false);
            await action(t, const Key('profile-save'), source);
            await action(t, const Key('profile-confirm-accept'), source);
            expect(port.commands, hasLength(1));
            expect(port.commands.single.$1, matches(RegExp(r'^[a-f0-9]{32}$')));
            expect(port.commands.single.$2, 'b' * 32);
            expect(port.commands.single.$3, {
              'externalContacts': [
                {'platform': 'Discord', 'value': 'new-private'},
              ],
              'publicShowExternalContacts': true,
            });
            expect(
              port.commands.single.$4,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(owner.model.dirty, isFalse);
            expect(owner.model.outcome?.status, 'accepted');
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      'profile native edit state composing and validation survive live styles $suite',
      (t) async {
        final port = MotionPort();
        addTearDown(port.changes.close);
        final live = await mount(t, editor(port), suite);
        final field = input('description');
        await t.ensureVisible(field);
        await t.tap(field);
        t.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'Draft abc',
            selection: TextSelection(baseOffset: 6, extentOffset: 9),
            composing: TextRange(start: 6, end: 9),
          ),
        );
        await t.pump();
        final native = t.state<FormFieldState<String>>(field);
        final edit = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        final controller = t.widget<EditableText>(edit).controller;
        final value = controller.value;
        live.change(() {
          live.suite = InteractionSuite.scan;
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        expect(t.state<FormFieldState<String>>(field), same(native));
        expect(t.widget<EditableText>(edit).controller, same(controller));
        expect(controller.value, value);
        expect(state(t).fields['description'], 'Draft abc');
        expect(port.commands, isEmpty);
        expect(native.validate(), isTrue);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'profile discard and reload cancellation retain editor before explicit reset $suite',
      (t) async {
        final port = MotionPort();
        addTearDown(port.changes.close);
        await mount(t, editor(port), suite);
        await t.ensureVisible(input('description'));
        await t.enterText(input('description'), 'Unsaved text');
        await settleCommunityImages(t);
        final native = t.state<FormFieldState<String>>(input('description'));
        for (final entry in ['profile-discard', 'profile-reload']) {
          await action(t, Key(entry), 'keyboard');
          await action(t, const Key('profile-confirm-cancel'), 'keyboard');
          expect(
            t.state<FormFieldState<String>>(input('description')),
            same(native),
          );
          expect(state(t).fields['description'], 'Unsaved text');
          expect(port.reads, 1);
          expect(port.commands, isEmpty);
        }
        await action(t, const Key('profile-discard'), 'keyboard');
        await action(t, const Key('profile-confirm-accept'), 'keyboard');
        expect(state(t).fields['description'], 'Original');
        expect(state(t).model.dirty, false);
        expect(
          t.state<FormFieldState<String>>(input('description')),
          isNot(same(native)),
        );
        expect(port.reads, 1);
        expect(port.commands, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'profile refresh failure cannot silently discard existing draft $suite',
      (t) async {
        final port = MotionPort();
        addTearDown(port.changes.close);
        await mount(t, editor(port), suite);
        state(t).update('description', 'Do not lose');
        await settleCommunityImages(t);
        port.readFails = true;
        await action(t, const Key('profile-reload'), 'keyboard');
        await action(t, const Key('profile-confirm-accept'), 'keyboard');
        expect(state(t).model.dirty, true);
        expect(state(t).fields['description'], 'Do not lose');
        expect(port.reads, 2);
        expect(port.commands, isEmpty);
        expect(state(t).saved, false);
        await t.pumpWidget(const SizedBox());
      },
    );

    for (final result in ['rejected', 'unknown']) {
      testWidgets(
        'profile pending $result retains draft no duplicate or false success $suite',
        (t) async {
          final port = MotionPort()
            ..pending = Completer<CommunityProfileOutcome>();
          addTearDown(port.changes.close);
          final live = await mount(t, editor(port), suite);
          await t.ensureVisible(input('description'));
          await t.enterText(input('description'), 'Retain rejected');
          await settleCommunityImages(t);
          await action(t, const Key('profile-save'), 'pointer', settle: false);
          expect(port.commands, hasLength(1));
          final save = t.widget<StarBridgeActionButton>(
            find.byWidgetPredicate(
              (w) =>
                  w is StarBridgeActionButton &&
                  w.controlKey == const Key('profile-save'),
            ),
          );
          expect(save.onActivate, isNull);
          live.change(() {
            live.reduce = true;
            live.light = true;
          });
          await t.pump();
          await t.pump();
          port.pending!.complete(
            CommunityProfileOutcome(
              result,
              error: result == 'unknown' ? 'outcomeUnknown' : 'dataInvalid',
            ),
          );
          await settleCommunityImages(t);
          expect(state(t).model.dirty, isTrue);
          expect(state(t).fields['description'], 'Retain rejected');
          expect(state(t).saved, isFalse);
          expect(port.commands, hasLength(1));
          expect(state(t).model.needsRefresh, result == 'unknown');
          if (result == 'unknown') {
            final answer = state(t).confirmLeave();
            await settleCommunityImages(t);
            expect(find.byKey(const Key('profile-leave-save')), findsNothing);
            await action(t, const Key('profile-leave-stay'), 'keyboard');
            expect(await answer, false);
            expect(port.commands, hasLength(1));
          }
          await t.pumpWidget(const SizedBox());
        },
      );
    }

    testWidgets(
      'profile owns confirmation retirement after account invalidation $suite',
      (t) async {
        final port = MotionPort();
        addTearDown(port.changes.close);
        await mount(t, editor(port), suite);
        state(t).update('description', 'Unsaved');
        await settleCommunityImages(t);
        await action(t, const Key('profile-discard'), 'pointer');
        expect(find.byType(AlertDialog), findsOneWidget);
        port.changes.add(null);
        await settleCommunityImages(t);
        expect(find.byType(AlertDialog), findsNothing);
        expect(state(t).dialogs, isEmpty);
        expect(state(t).model.invalidated, isTrue);
        expect(port.commands, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'profile pending response after departure cannot revive editor $suite',
      (t) async {
        final port = MotionPort()
          ..pending = Completer<CommunityProfileOutcome>();
        addTearDown(port.changes.close);
        final live = await mount(t, editor(port), suite);
        state(t).update('description', 'Sent draft');
        await settleCommunityImages(t);
        await action(t, const Key('profile-save'), 'keyboard', settle: false);
        live.change(() => live.visible = false);
        await t.pump();
        port.pending!.complete(
          const CommunityProfileOutcome('accepted', revision: 8),
        );
        await settleCommunityImages(t);
        expect(find.byType(CommunityProfileDialog), findsNothing);
        expect(port.commands, hasLength(1));
        expect(port.saves, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'profile read-only permission not promoted by styled controls $suite',
      (t) async {
        final port = MotionPort();
        port.profile['access'] = {
          'canEditProfile': false,
          'canEditLogo': true,
          'canEditBanner': false,
        };
        addTearDown(port.changes.close);
        await mount(t, editor(port), suite);
        expect(t.widget<TextFormField>(input('description')).enabled, isFalse);
        expect(toggle('emailNotificationsEnabled'), findsNothing);
        final remove = find.byWidgetPredicate(
          (w) =>
              w is StarBridgeActionButton &&
              w.controlKey == const Key('profile-remove-logo'),
        );
        expect(t.widget<StarBridgeActionButton>(remove).onActivate, isNotNull);
        await action(t, const Key('profile-remove-logo'), 'keyboard');
        await action(t, const Key('profile-save'), 'keyboard');
        expect(port.commands.single.$3, {'clearLogoImage': true});
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'profile open confirmation follows live reduce and theme within two frames $suite',
      (t) async {
        final port = MotionPort();
        addTearDown(port.changes.close);
        final live = await mount(t, editor(port), suite);
        state(t).update('description', 'Retain');
        await settleCommunityImages(t);
        await action(t, const Key('profile-discard'), 'pointer', settle: false);
        final route =
            ModalRoute.of(t.element(find.byType(AlertDialog)))!
                as StarBridgeDialogRoute;
        live.change(() {
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        expect(route.animation!.value, 1);
        expect(
          Theme.of(t.element(find.byType(AlertDialog))).brightness,
          Brightness.light,
        );
        await action(t, const Key('profile-confirm-cancel'), 'keyboard');
        expect(state(t).model.dirty, isTrue);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'native filter and explanation row geometry retained at $scale',
      (t) async {
        await mount(
          t,
          Builder(
            builder: (context) => Column(
              children: [
                const StarBridgeChoiceChip.filter(
                  controlKey: Key('new-filter'),
                  label: 'English',
                  selected: true,
                ),
                const FilterChip(
                  key: Key('old-filter'),
                  label: Text('English'),
                  selected: true,
                  onSelected: null,
                ),
                StarBridgeCheckboxTile(
                  key: const Key('new-check-row'),
                  label: 'Next day',
                  titleWidget: Text(
                    'Next day',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  subtitle: 'Explanation',
                  dense: false,
                  trailingControl: true,
                  value: true,
                ),
                CheckboxListTile(
                  key: const Key('old-check-row'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Next day',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  subtitle: const Text('Explanation'),
                  value: true,
                  onChanged: null,
                ),
              ],
            ),
          ),
          InteractionSuite.standard,
          scale: scale,
        );
        expect(
          t.getSize(find.byKey(const Key('new-filter'))),
          t.getSize(find.byKey(const Key('old-filter'))),
        );
        expect(
          t.getSize(find.byKey(const Key('new-check-row'))).height,
          t.getSize(find.byKey(const Key('old-check-row'))).height,
        );
        final rendered = t.widget<StarBridgeCheckboxTile>(
          find.byKey(const Key('new-check-row')),
        );
        expect(rendered.trailingControl, true);
        expect(rendered.subtitle, 'Explanation');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('profile confirmation painted review $suite', (t) async {
      final port = MotionPort();
      addTearDown(port.changes.close);
      final capture = GlobalKey();
      await mount(t, editor(port), suite, capture: capture, scale: 2);
      await t.ensureVisible(input('description'));
      await t.enterText(input('description'), 'Preserved draft');
      await settleCommunityImages(t);
      await action(t, const Key('profile-discard'), 'pointer');
      await t.pump(const Duration(milliseconds: 500));
      final rectangles = [
        for (final e
            in find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(Text),
                )
                .evaluate()
                .take(3))
          t.getRect(find.byWidget(e.widget)),
      ];
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        final raw = (await image.toByteData(format: ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
        final counts = <int>[];
        for (final rect in rectangles) {
          var count = 0;
          for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
            for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
              final n = (y * image.width + x) * 4;
              if (raw[n] >= 120 &&
                  raw[n + 1] >= 140 &&
                  raw[n + 2] >= 145 &&
                  raw[n + 3] >= 240) {
                count++;
              }
            }
          }
          counts.add(count);
        }
        expect(
          counts,
          everyElement(greaterThan(5)),
          reason: 'Confirmation title, body and cancel label paint actual readable foreground.',
        );
        Directory('build/reviews/interaction-batch3af')
            .createSync(recursive: true);
        File(
          'build/reviews/interaction-batch3af/${suite.name}-profile-confirm-200.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
