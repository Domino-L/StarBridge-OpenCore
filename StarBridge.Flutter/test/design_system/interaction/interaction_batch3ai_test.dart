import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_choice_chip.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/communities_page.dart';
import 'package:starbridge_flutter/features/communities/community_creation_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_creation_port.dart';
import 'package:starbridge_flutter/features/communities/community_filter_panel.dart';
import 'package:starbridge_flutter/features/communities/community_logo_crop.dart';
import 'package:starbridge_flutter/features/communities/community_logo_port.dart';
import 'package:starbridge_flutter/features/communities/community_tag_picker.dart';

import 'interaction_batch3ae_test.dart' show mount, action;
import 'interaction_batch3af_test.dart' show activate;
import '../../features/communities/community_creation_dialog_test.dart'
    show FormPort;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../../features/friends/social_layout_test.dart' show loadFonts;

class MotionPort extends FormPort {
  final sources = <(String, InteractionSource)>[];
  String? intent;
  bool loadFail = false;
  Completer<CommunityCreationOutcome>? pending;
  Completer<CommunityLogoSource?>? picking;
  @override
  Future<CommunityCreationOptions> creationOptions() async {
    if (loadFail) throw StateError('load failed');
    return super.creationOptions();
  }

  @override
  Future<CommunityCreationOutcome> createCommunity(
    String requestId,
    Map<String, Object?> draft,
  ) async {
    intent = requestId;
    sources.add(('create', currentStarBridgeActivationSource));
    writes.add(draft);
    return pending?.future ?? Future.value(result);
  }

  @override
  Future<CommunityLogoSource?> pickLogo() async {
    sources.add(('pick', currentStarBridgeActivationSource));
    if (picking != null) {
      picks++;
      return picking!.future;
    }
    return super.pickLogo();
  }

  @override
  Future<String> cropLogo(String ref, double x, double y, double size) {
    sources.add(('crop', currentStarBridgeActivationSource));
    return super.cropLogo(ref, x, y, size);
  }
}

Future<void> fill(WidgetTester t) async {
  for (final entry in {
    'name': '  Motion Fleet  ',
    'code': ' motion ',
  }.entries) {
    final target = find.byKey(ValueKey('create-${entry.key}'));
    await t.ensureVisible(target);
    await t.enterText(target, entry.value);
  }
  await settleCommunityImages(t);
}

Future<void> reveal(WidgetTester t, Finder target) async {
  if (target.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      target,
      220,
      scrollable: find
          .descendant(
            of: find.byType(CommunityFilterPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await t.ensureVisible(target);
  await settleCommunityImages(t);
}

Finder checkbox(Key key) => find.byWidgetPredicate(
  (w) => w is StarBridgeCheckboxTile && w.controlKey == key,
);
Finder chip(Key key) => find.byWidgetPredicate(
  (w) => w is StarBridgeChoiceChip && w.controlKey == key,
);

Future<void> activateFilterHeader(
  WidgetTester t,
  Finder target,
  String source,
) async {
  if (source != 'keyboard') {
    await activate(t, target, source);
    return;
  }
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  final expander = find.descendant(
    of: target,
    matching: find.byType(SuiteExpander),
  );
  expect(expander, findsOneWidget);
  final before = t.widget<SuiteExpander>(expander);
  final focus = before.focusNode;
  expect(focus, isNotNull);
  expect(focus!.canRequestFocus, isTrue);
  focus.requestFocus();
  await t.pump();
  expect(FocusManager.instance.primaryFocus, same(focus));
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await settleCommunityImages(t);
  expect(t.widget<SuiteExpander>(expander).expanded, !before.expanded);
}

void routeSource(WidgetTester t, Finder child, String source) {
  final route = ModalRoute.of(t.element(child))! as StarBridgeDialogRoute;
  expect(route.instant, source != 'pointer');
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'production directory creation tags logo explicit confirmation $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = MotionPort();
          final module = CommunitiesModule(port);
          addTearDown(module.dispose);
          addTearDown(port.changes.close);
          try {
            await mount(
              t,
              CommunitiesPage(createPort: () => port, module: module),
              suite,
            );
            await action(t, const Key('community-create-open'), source);
            routeSource(t, find.byType(CommunityCreationDialog), source);
            await fill(t);
            final nativeNameState = t.state(
              find.byKey(const ValueKey('create-name')),
            );
            await action(t, const Key('community-create-tags'), source);
            routeSource(t, find.byType(CommunityTagPicker), source);
            await activate(
              t,
              checkbox(const ValueKey('tag-scouting-control')),
              source,
            );
            await action(t, const Key('community-tag-apply'), source);
            await action(t, const Key('community-create-pick-logo'), source);
            routeSource(t, find.byType(CommunityLogoCrop), source);
            await action(t, const Key('community-crop-apply'), source);
            expect(port.writes, isEmpty);
            expect(port.clears, 1);
            await action(t, const Key('community-create-submit'), source);
            routeSource(t, find.byType(AlertDialog), source);
            await action(
              t,
              const Key('community-create-confirm-cancel'),
              source,
            );
            expect(port.writes, isEmpty);
            expect(
              t.state(find.byKey(const ValueKey('create-name'))),
              same(nativeNameState),
            );
            expect(
              t
                  .widget<EditableText>(
                    find.descendant(
                      of: find.byKey(const ValueKey('create-name')),
                      matching: find.byType(EditableText),
                    ),
                  )
                  .controller
                  .text,
              '  Motion Fleet  ',
            );
            await action(t, const Key('community-create-submit'), source);
            await action(t, const Key('community-create-confirm-save'), source);
            final sent = port.writes.single;
            expect(sent['name'], 'Motion Fleet');
            expect(sent['code'], 'MOTION');
            expect(sent['tagIds'], ['scouting']);
            expect(sent['logoImageData'], FormPort.image);
            expect(sent['activeFrom'], '19:00');
            expect(sent['activeTo'], '22:00');
            expect(sent['timeZoneId'], 'UTC');
            expect(sent['activeSystemIds'], ['stanton']);
            expect(port.intent, matches(RegExp(r'^[a-f0-9]{32}$')));
            expect(
              port.sources,
              everyElement(
                predicate<(String, InteractionSource)>(
                  (v) =>
                      v.$2 ==
                      (source == 'pointer'
                          ? InteractionSource.pointer
                          : InteractionSource.keyboard),
                ),
              ),
            );
            expect(find.byType(CommunityCreationDialog), findsNothing);
            expect(module.selected?.name, 'Test Organization');
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets(
        'all directory filter groups retain private draft and wire values $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          final applied = <String>[];
          try {
            await mount(
              t,
              CommunityFilterPanel(onApply: applied.add),
              suite,
              width: 520,
            );
            for (final group in communityFilterGroups.entries) {
              final header = find.byKey(ValueKey('org-filter-${group.key}'));
              await reveal(t, header);
              if (!const ['join', 'status', 'scale'].contains(group.key)) {
                await activateFilterHeader(t, header, source);
              }
              final key = ValueKey(
                'community-filter-${group.key}-${group.value.first}',
              );
              await reveal(t, checkbox(key));
              await activate(t, checkbox(key), source);
              expect(
                t.widget<StarBridgeCheckboxTile>(checkbox(key)).value,
                true,
              );
            }
            expect(applied, isEmpty);
            await action(t, const Key('community-filter-apply'), source);
            final sent = jsonDecode(applied.single) as Map;
            for (final group in communityFilterGroups.entries) {
              expect(sent[group.key], [group.value.first]);
            }
            expect(sent['language'], '');
            expect(sent['offset'], DateTime.now().timeZoneOffset.inMinutes);
            await action(t, const Key('community-filter-reset'), source);
            expect(applied.last, '{}');
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    for (final status in ['rejected', 'unknown']) {
      testWidgets(
        'create pending then $status preserves original policy $suite',
        (t) async {
          final port = MotionPort()
            ..pending = Completer<CommunityCreationOutcome>();
          addTearDown(port.changes.close);
          final live = await mount(
            t,
            CommunityCreationDialog(
              port: port,
              invalidations: port.invalidations,
            ),
            suite,
          );
          await fill(t);
          await action(t, const Key('community-create-submit'), 'keyboard');
          await action(
            t,
            const Key('community-create-confirm-save'),
            'keyboard',
            settle: false,
          );
          expect(port.writes, hasLength(1));
          expect(
            t
                .widget<StarBridgeActionButton>(
                  find.byWidgetPredicate(
                    (w) =>
                        w is StarBridgeActionButton &&
                        w.controlKey == const Key('community-create-submit'),
                  ),
                )
                .onActivate,
            isNull,
          );
          live.change(() {
            live.reduce = true;
            live.light = true;
          });
          await t.pump();
          await t.pump();
          port.pending!.complete(
            CommunityCreationOutcome(
              status,
              error: status == 'rejected'
                  ? 'codeUnavailable'
                  : 'outcomeUnknown',
            ),
          );
          await settleCommunityImages(t);
          expect(find.byType(CommunityCreationDialog), findsOneWidget);
          final button = t.widget<StarBridgeActionButton>(
            find.byWidgetPredicate(
              (w) =>
                  w is StarBridgeActionButton &&
                  w.controlKey == const Key('community-create-submit'),
            ),
          );
          expect(button.onActivate == null, status == 'unknown');
          expect(port.writes, hasLength(1));
          expect(
            t
                .widget<EditableText>(
                  find.descendant(
                    of: find.byKey(const ValueKey('create-name')),
                    matching: find.byType(EditableText),
                  ),
                )
                .controller
                .text,
            '  Motion Fleet  ',
          );
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'create discard cancel preserves draft and explicit discard exits $suite',
      (t) async {
        final port = MotionPort();
        addTearDown(port.changes.close);
        await mount(
          t,
          Builder(
            builder: (context) => StarBridgeActionButton(
              controlKey: const Key('open'),
              onActivate: (source) => showStarBridgeDialog(
                context,
                source: source,
                builder: (_) => CommunityCreationDialog(
                  port: port,
                  invalidations: port.invalidations,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
          suite,
        );
        await action(t, const Key('open'), 'keyboard');
        await fill(t);
        await action(t, const Key('community-create-leave'), 'keyboard');
        await action(
          t,
          const Key('community-create-discard-cancel'),
          'keyboard',
        );
        expect(find.byType(CommunityCreationDialog), findsOneWidget);
        expect(port.writes, isEmpty);
        await action(t, const Key('community-create-leave'), 'keyboard');
        await action(
          t,
          const Key('community-create-discard-confirm'),
          'keyboard',
        );
        expect(find.byType(CommunityCreationDialog), findsNothing);
        expect(port.writes, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'create local logo remove never writes and systems FormField stays native $suite',
      (t) async {
        final port = MotionPort();
        addTearDown(port.changes.close);
        await mount(
          t,
          CommunityCreationDialog(
            port: port,
            invalidations: port.invalidations,
          ),
          suite,
        );
        await action(t, const Key('community-create-pick-logo'), 'keyboard');
        await action(t, const Key('community-crop-apply'), 'keyboard');
        await action(t, const Key('community-create-remove-logo'), 'keyboard');
        expect(
          find.byKey(const Key('community-create-remove-logo')),
          findsNothing,
        );
        expect(port.writes, isEmpty);
        await fill(t);
        await activate(
          t,
          chip(const ValueKey('community-create-system-stanton')),
          'keyboard',
        );
        await action(t, const Key('community-create-submit'), 'keyboard');
        expect(
          find.byKey(const Key('community-create-confirm-save')),
          findsNothing,
        );
        expect(find.text('请至少选择一个星系。'), findsOneWidget);
        await activate(
          t,
          chip(const ValueKey('community-create-system-pyro')),
          'keyboard',
        );
        await action(t, const Key('community-create-submit'), 'keyboard');
        await action(t, const Key('community-create-confirm-save'), 'keyboard');
        expect(port.writes.single['activeSystemIds'], ['pyro']);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'creation options fail then explicit reload stays one original controller $suite',
      (t) async {
        final port = MotionPort()..loadFail = true;
        addTearDown(port.changes.close);
        await mount(
          t,
          CommunityCreationDialog(
            port: port,
            invalidations: port.invalidations,
          ),
          suite,
        );
        expect(
          find.byKey(const Key('community-create-reload')),
          findsOneWidget,
        );
        port.loadFail = false;
        await action(t, const Key('community-create-reload'), 'keyboard');
        expect(find.byKey(const ValueKey('create-name')), findsOneWidget);
        expect(port.writes, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final child in ['tags', 'logo', 'confirm']) {
      testWidgets(
        'create invalidation retires $child owned routes without write $suite',
        (t) async {
          final port = MotionPort(), module = CommunitiesModule(port);
          addTearDown(port.changes.close);
          addTearDown(module.dispose);
          await mount(
            t,
            CommunitiesPage(createPort: () => port, module: module),
            suite,
          );
          await action(t, const Key('community-create-open'), 'keyboard');
          if (child == 'confirm') await fill(t);
          await action(
            t,
            Key(
              child == 'tags'
                  ? 'community-create-tags'
                  : child == 'logo'
                  ? 'community-create-pick-logo'
                  : 'community-create-submit',
            ),
            'keyboard',
          );
          port.changes.add(null);
          await settleCommunityImages(t);
          expect(find.byType(CommunityCreationDialog), findsNothing);
          expect(find.byType(CommunityTagPicker), findsNothing);
          expect(find.byType(CommunityLogoCrop), findsNothing);
          expect(find.byType(AlertDialog), findsNothing);
          expect(port.writes, isEmpty);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'directory tags private cancel names removal and invalidation $suite',
      (t) async {
        final applied = <String>[];
        final changes = StreamController<void>.broadcast(sync: true);
        addTearDown(changes.close);
        final live = await mount(
          t,
          CommunityFilterPanel(
            onApply: applied.add,
            invalidations: changes.stream,
            value: '{"tags":["探索"]}',
          ),
          suite,
          width: 520,
        );
        await reveal(t, find.byKey(const Key('choose-filter-tags')));
        await action(t, const Key('choose-filter-tags'), 'keyboard');
        await activate(
          t,
          checkbox(const ValueKey('tag-core_combat-control')),
          'keyboard',
        );
        await action(t, const Key('community-tag-cancel'), 'keyboard');
        expect(find.byKey(const ValueKey('filter-tag-战斗')), findsNothing);
        await action(t, const Key('choose-filter-tags'), 'keyboard');
        await activate(
          t,
          checkbox(const ValueKey('tag-core_combat-control')),
          'keyboard',
        );
        await action(t, const Key('community-tag-apply'), 'keyboard');
        expect(applied, isEmpty);
        await action(t, const Key('community-filter-apply'), 'keyboard');
        expect(jsonDecode(applied.single)['tags'], ['战斗', '探索']);
        await reveal(t, find.byKey(const ValueKey('filter-tag-战斗')));
        if (suite == InteractionSuite.standard) {
          final focus = find
              .ancestor(
                of: find.byKey(const ValueKey('filter-tag-战斗')),
                matching: find.byWidgetPredicate(
                  (w) => w is Focus && w.focusNode?.canRequestFocus == true,
                ),
              )
              .first;
          t.widget<Focus>(focus).focusNode!.requestFocus();
        } else {
          t
              .widget<SuitePressable>(
                find.byKey(
                  const ValueKey<Object>(('chip-remove', 'filter-tag-战斗')),
                ),
              )
              .focusNode!
              .requestFocus();
        }
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.delete);
        await settleCommunityImages(t);
        await action(t, const Key('community-filter-apply'), 'keyboard');
        expect(jsonDecode(applied.last)['tags'], ['探索']);
        await reveal(t, find.byKey(const Key('choose-filter-tags')));
        await action(t, const Key('choose-filter-tags'), 'pointer');
        live.change(() {
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        expect(
          InteractionScope.of(t.element(find.byType(CommunityTagPicker)))
              .reduceMotion,
          true,
        );
        changes.add(null);
        await settleCommunityImages(t);
        expect(find.byType(CommunityTagPicker), findsNothing);
        await action(t, const Key('community-filter-apply'), 'keyboard');
        expect(applied, hasLength(2));
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'create confirmation live reduce and mixed source continue to original writer $suite',
      (t) async {
        final port = MotionPort()
          ..result = const CommunityCreationOutcome(
            'rejected',
            error: 'codeUnavailable',
          );
        addTearDown(port.changes.close);
        final live = await mount(
          t,
          CommunityCreationDialog(
            port: port,
            invalidations: port.invalidations,
          ),
          suite,
        );
        await fill(t);
        await action(
          t,
          const Key('community-create-submit'),
          'pointer',
          settle: false,
        );
        live.change(() {
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        final dialog = find.byType(AlertDialog);
        expect(InteractionScope.of(t.element(dialog)).reduceMotion, true);
        final route =
            ModalRoute.of(t.element(dialog))! as StarBridgeDialogRoute;
        expect(route.animation!.value, 1);
        await action(t, const Key('community-create-confirm-save'), 'keyboard');
        expect(port.writes, hasLength(1));
        expect(port.sources.single, ('create', InteractionSource.keyboard));
        expect(find.byType(CommunityCreationDialog), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'create late native picker after departure never crops or writes $suite',
      (t) async {
        final port = MotionPort()..picking = Completer<CommunityLogoSource?>();
        addTearDown(port.changes.close);
        final live = await mount(
          t,
          CommunityCreationDialog(
            port: port,
            invalidations: port.invalidations,
          ),
          suite,
        );
        await action(
          t,
          const Key('community-create-pick-logo'),
          'keyboard',
          settle: false,
        );
        live.change(() => live.visible = false);
        await t.pump();
        port.picking!.complete(
          const CommunityLogoSource('old', FormPort.image, 300, 200),
        );
        await settleCommunityImages(t);
        expect(port.crops, 0);
        expect(port.clears, 1);
        expect(port.writes, isEmpty);
        expect(find.byType(CommunityLogoCrop), findsNothing);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'create accepted late answer after invalidation cannot reopen organization $suite',
      (t) async {
        final port = MotionPort()
          ..pending = Completer<CommunityCreationOutcome>();
        final module = CommunitiesModule(port);
        addTearDown(module.dispose);
        addTearDown(port.changes.close);
        await mount(
          t,
          CommunitiesPage(createPort: () => port, module: module),
          suite,
        );
        await action(t, const Key('community-create-open'), 'keyboard');
        await fill(t);
        await action(t, const Key('community-create-submit'), 'keyboard');
        await action(
          t,
          const Key('community-create-confirm-save'),
          'keyboard',
          settle: false,
        );
        port.changes.add(null);
        await settleCommunityImages(t);
        port.pending!.complete(port.result);
        await settleCommunityImages(t);
        expect(find.byType(CommunityCreationDialog), findsNothing);
        expect(module.selected, isNull);
        expect(port.writes, hasLength(1));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'create stale tag entry double callback still owns one picker $suite',
      (t) async {
        final port = MotionPort();
        addTearDown(port.changes.close);
        await mount(
          t,
          CommunityCreationDialog(
            port: port,
            invalidations: port.invalidations,
          ),
          suite,
        );
        final entry = t.widget<StarBridgeActionButton>(
          find.byWidgetPredicate(
            (w) =>
                w is StarBridgeActionButton &&
                w.controlKey == const Key('community-create-tags'),
          ),
        );
        entry.onActivate!(InteractionSource.keyboard);
        entry.onActivate!(InteractionSource.keyboard);
        await settleCommunityImages(t);
        expect(
          find.byType(CommunityTagPicker, skipOffstage: false),
          findsOneWidget,
        );
        await action(t, const Key('community-tag-cancel'), 'keyboard');
        expect(
          find.byType(CommunityTagPicker, skipOffstage: false),
          findsNothing,
        );
        expect(port.writes, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets('directory parent departure retires open tag picker $suite', (
      t,
    ) async {
      final live = await mount(
        t,
        CommunityFilterPanel(onApply: (_) => fail('no write')),
        suite,
        width: 520,
      );
      await reveal(t, find.byKey(const Key('choose-filter-tags')));
      await action(t, const Key('choose-filter-tags'), 'keyboard');
      live.change(() => live.visible = false);
      await settleCommunityImages(t);
      expect(find.byType(CommunityTagPicker), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('create confirmation visible pixels review $suite', (t) async {
      final port = MotionPort(), capture = GlobalKey();
      addTearDown(port.changes.close);
      await mount(
        t,
        CommunityCreationDialog(port: port, invalidations: port.invalidations),
        suite,
        capture: capture,
      );
      await fill(t);
      await action(t, const Key('community-create-submit'), 'pointer');
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final rectangles = <Rect>[];
      // Confirm body includes the original draft whitespace and policy copy.
      for (final e
          in find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Text),
              )
              .evaluate()
              .take(3)) {
        rectangles.add(t.getRect(find.byWidget(e.widget)));
      }
      await t.runAsync(() async {
        final image = await boundary.toImage();
        final raw = (await image.toByteData(format: ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
        for (final rect in rectangles) {
          var count = 0;
          for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
            for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
              final i = (y * image.width + x) * 4;
              if (raw[i] >= 120 &&
                  raw[i + 1] >= 140 &&
                  raw[i + 2] >= 145 &&
                  raw[i + 3] > 240) {
                count++;
              }
            }
          }
          expect(count, greaterThan(10));
        }
        final png = await image.toByteData(format: ImageByteFormat.png);
        Directory('build/reviews/interaction-batch3ai')
            .createSync(recursive: true);
        File(
          'build/reviews/interaction-batch3ai/${suite.name}-create-confirm.png',
        ).writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
