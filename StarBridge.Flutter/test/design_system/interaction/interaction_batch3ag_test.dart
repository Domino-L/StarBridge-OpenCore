import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_choice_chip.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_removable_chip_group.dart';
import 'package:starbridge_flutter/features/communities/community_creation_port.dart';
import 'package:starbridge_flutter/features/communities/community_logo_crop.dart';
import 'package:starbridge_flutter/features/communities/community_logo_port.dart';
import 'package:starbridge_flutter/features/communities/community_tag_picker.dart';
import 'package:starbridge_flutter/features/communities/community_profile_dialog.dart';
import 'package:starbridge_flutter/features/communities/legacy_community_tag_catalog.dart';

import 'interaction_batch3ae_test.dart' show mount, action;
import 'interaction_batch3af_test.dart' show activate;
import '../../features/communities/community_creation_dialog_test.dart'
    show FormPort;
import '../../features/communities/community_profile_dialog_test.dart'
    show EditorPort;
import '../../features/communities/community_creation_bridge_test.dart'
    show optionsPayload;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../../features/friends/social_layout_test.dart' show loadFonts;

CommunityCreationOptions options({bool quota = false}) {
  final data = optionsPayload();
  data['categories'] = [
    {
      'id': 'core',
      'name': 'Core',
      'accentHex': '#55AACC',
      'description': 'Core description',
    },
    {
      'id': 'other',
      'name': 'Other',
      'accentHex': '#77CC99',
      'description': 'Other description',
    },
  ];
  data['tags'] = [
    for (var i = 0; i < 7; i++)
      {
        'id': 'tag$i',
        'name': 'Activity $i',
        'categoryId': quota && i < 4 ? 'core' : 'other',
        'description': 'Description $i',
      },
  ];
  return CommunityCreationOptions.parse(data);
}

class CropPort implements CommunityLogoPort {
  final calls = <(String, double, double, double)>[];
  Completer<String>? pending;
  bool fail = false;
  @override
  bool get canPickLogo => true;
  @override
  Future<CommunityLogoSource?> pickLogo() async => source;
  static const source = CommunityLogoSource(
    'a-source',
    FormPort.image,
    300,
    200,
  );
  @override
  Future<void> clearLogo() async {}
  @override
  Future<String> cropLogo(String ref, double x, double y, double size) {
    calls.add((ref, x, y, size));
    if (pending != null) return pending!.future;
    if (fail) return Future.error(StateError('crop failed'));
    return Future.value(FormPort.image);
  }
}

class ProfileCropPort extends EditorPort {
  final crop = CropPort();
  Completer<CommunityLogoSource?>? picking;
  @override
  Future<CommunityLogoSource?> pickLogo() =>
      picking?.future ?? Future.value(CropPort.source);
  @override
  Future<String> cropLogo(String ref, double x, double y, double size) =>
      crop.cropLogo(ref, x, y, size);
}

class ProfileTagPort extends EditorPort {
  @override
  Future<CommunityCreationOptions> creationOptions() async =>
      LegacyCommunityTagCatalog.options;
}

Widget launch<T>(WidgetBuilder build, void Function(T?) received) => Builder(
  builder: (context) => StarBridgeActionButton(
    controlKey: const Key('launch'),
    child: const Text('Open'),
    onActivate: (source) async {
      received(
        await showStarBridgeDialog<T>(context, source: source, builder: build),
      );
    },
  ),
);

Finder tag(String id) => find.byKey(ValueKey('tag-$id'));
Future<void> remove(WidgetTester t, String id, String source) async {
  final data = t.widget<StarBridgeRemovableChipGroup>(
    find.byType(StarBridgeRemovableChipGroup),
  );
  final chip = data.chips.firstWhere((c) => c.id == 'selected-$id');
  final suite = InteractionScope.of(
    t.element(find.byType(StarBridgeRemovableChipGroup)),
  ).suite;
  if (suite == InteractionSuite.standard) {
    final target = find.byKey(ValueKey(chip.id));
    await t.ensureVisible(target);
    if (source == 'pointer') {
      final icon = find
          .descendant(of: target, matching: find.byType(Icon))
          .last;
      await t.tap(icon);
    } else if (source == 'keyboard') {
      final focus = find
          .ancestor(
            of: target,
            matching: find.byWidgetPredicate(
              (w) => w is Focus && w.focusNode?.canRequestFocus == true,
            ),
          )
          .first;
      t.widget<Focus>(focus).focusNode!.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.delete);
    } else {
      final node = find.descendant(
        of: target,
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.onTap != null,
        ),
      );
      final semantics = t.getSemantics(node.last);
      t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        semantics.id,
        SemanticsAction.tap,
      );
    }
  } else {
    final key = ValueKey<Object>(('chip-remove', chip.id));
    if (source == 'keyboard') {
      t.widget<SuitePressable>(find.byKey(key)).focusNode!.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.delete);
    } else {
      await action(t, key, source, settle: false);
    }
  }
  await settleCommunityImages(t);
}

Future<void> slider(WidgetTester t, String name, String source) async {
  final f = find.byKey(ValueKey('crop-$name'));
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  if (source == 'pointer') {
    final rect = t.getRect(f);
    await t.tapAt(Offset(rect.left + rect.width * .7, rect.center.dy));
  } else if (source == 'keyboard') {
    t.widget<Slider>(f).focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
  } else {
    final root = t.getSemantics(find.byKey(ValueKey('crop-$name-semantics')));
    final nodes = <SemanticsNode>[];
    void collect(SemanticsNode n) {
      if (n.getSemanticsData().hasAction(SemanticsAction.decrease)) {
        nodes.add(n);
      }
      n.visitChildren((child) {
        collect(child);
        return true;
      });
    }

    collect(root);
    final node = nodes.single;
    expect(node.getSemanticsData().hasAction(SemanticsAction.decrease), true);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.decrease,
    );
  }
  await settleCommunityImages(t);
}

double value(WidgetTester t, String name) =>
    t.widget<Slider>(find.byKey(ValueKey('crop-$name'))).value;
void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'actual profile tag application retains private save owner $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = ProfileTagPort();
          addTearDown(port.changes.close);
          try {
            await mount(
              t,
              CommunityProfileDialog(
                port: port,
                targetRef: 'a' * 32,
                embedded: true,
              ),
              suite,
            );
            await action(t, const Key('profile-choose-tags'), source);
            final route =
                ModalRoute.of(t.element(find.byType(CommunityTagPicker)))!
                    as StarBridgeDialogRoute;
            expect(route.instant, source != 'pointer');
            final core = LegacyCommunityTagCatalog.tags.firstWhere(
              (tag) => tag.categoryId == 'core',
            );
            await activate(t, tag(core.id), source);
            await action(t, const Key('community-tag-apply'), source);
            final owner = t.state<CommunityProfileDialogState>(
              find.byType(CommunityProfileDialog),
            );
            expect(owner.fields['type'], core.name);
            expect(owner.model.dirty, true);
            expect(port.saves, isEmpty);
            await action(t, const Key('profile-choose-tags'), source);
            await action(t, const Key('community-tag-clear'), source);
            await action(t, const Key('community-tag-cancel'), source);
            expect(owner.fields['type'], core.name);
            expect(port.saves, isEmpty);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets(
        'tag private copy quota search category delete and apply $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final original = ['tag0', 'tag1', 'tag2', 'tag3', 'tag4'];
            List<String>? result;
            var completed = 0;
            await mount(
              t,
              launch<List<String>>(
                (_) =>
                    CommunityTagPicker(options: options(), selected: original),
                (r) {
                  result = r;
                  completed++;
                },
              ),
              suite,
            );
            await action(t, const Key('launch'), source);
            expect(
              t.widget<StarBridgeCheckboxTile>(tag('tag5')).onChanged,
              isNull,
            );
            await action(t, const Key('community-tag-clear'), source);
            expect(original, hasLength(5));
            expect(completed, 0);
            await activate(
              t,
              find.byWidgetPredicate(
                (w) =>
                    w is StarBridgeChoiceChip &&
                    w.controlKey == const ValueKey('category-core'),
              ),
              source,
            );
            expect(tag('tag5'), findsNothing);
            await activate(
              t,
              find.byWidgetPredicate(
                (w) =>
                    w is StarBridgeChoiceChip &&
                    w.controlKey == const ValueKey('category-other'),
              ),
              source,
            );
            expect(tag('tag5'), findsOneWidget);
            await activate(
              t,
              find.byWidgetPredicate(
                (w) =>
                    w is StarBridgeChoiceChip &&
                    w.controlKey == const Key('community-tag-all'),
              ),
              source,
            );
            await activate(t, tag('tag5'), source);
            expect(find.byKey(const ValueKey('selected-tag5')), findsOneWidget);
            await remove(t, 'tag5', source);
            expect(find.byKey(const ValueKey('selected-tag5')), findsNothing);
            await t.enterText(
              find.byKey(const Key('community-tag-search')),
              'Description 6',
            );
            await t.pumpAndSettle();
            expect(tag('tag6'), findsOneWidget);
            expect(tag('tag0'), findsNothing);
            await activate(t, tag('tag6'), source);
            await action(t, const Key('community-tag-apply'), source);
            expect(result, ['tag6']);
            expect(original, ['tag0', 'tag1', 'tag2', 'tag3', 'tag4']);
            expect(completed, 1);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
      testWidgets('crop source math exact explicit apply $suite $source', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        try {
          final port = CropPort();
          String? result;
          var completed = 0;
          await mount(
            t,
            launch<String>(
              (_) => CommunityLogoCrop(port: port, source: CropPort.source),
              (r) {
                result = r;
                completed++;
              },
            ),
            suite,
          );
          await action(t, const Key('launch'), source);
          for (final name in ['size', 'horizontal', 'vertical']) {
            await slider(t, name, source);
          }
          final size = value(t, 'size'),
              x = value(t, 'horizontal'),
              y = value(t, 'vertical');
          expect(port.calls, isEmpty);
          final side = math.min(300, 200) * size;
          await action(t, const Key('community-crop-apply'), source);
          expect(port.calls, hasLength(1));
          expect(port.calls.single.$1, 'a-source');
          expect(port.calls.single.$2, closeTo(x * (300 - side) / 300, 1e-9));
          expect(port.calls.single.$3, closeTo(y * (200 - side) / 200, 1e-9));
          expect(port.calls.single.$4, size);
          expect(result, FormPort.image);
          expect(completed, 1);
          await t.pumpWidget(const SizedBox());
        } finally {
          semantics.dispose();
        }
      });
    }
    testWidgets(
      'tag minimum core and capacity preserve disabled actions $suite',
      (t) async {
        List<String>? result;
        await mount(
          t,
          launch<List<String>>(
            (_) => CommunityTagPicker(
              options: options(quota: true),
              selected: const [],
              profileQuotas: true,
            ),
            (r) => result = r,
          ),
          suite,
        );
        await action(t, const Key('launch'), 'pointer');
        Finder apply() => find.byWidgetPredicate(
          (w) =>
              w is StarBridgeActionButton &&
              w.controlKey == const Key('community-tag-apply'),
        );
        expect(t.widget<StarBridgeActionButton>(apply()).onActivate, isNull);
        for (final id in ['tag0', 'tag1', 'tag2']) {
          await activate(t, tag(id), 'keyboard');
        }
        expect(t.widget<StarBridgeCheckboxTile>(tag('tag3')).onChanged, isNull);
        expect(t.widget<StarBridgeActionButton>(apply()).onActivate, isNotNull);
        await action(t, const Key('community-tag-cancel'), 'keyboard');
        expect(result, isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'actual profile no-pump rapid tag launch keeps one owned picker $suite',
      (t) async {
        final port = ProfileTagPort();
        addTearDown(port.changes.close);
        await mount(
          t,
          CommunityProfileDialog(
            port: port,
            targetRef: 'a' * 32,
            embedded: true,
          ),
          suite,
        );
        final button = find.byKey(const Key('profile-choose-tags'));
        await t.ensureVisible(button);
        await t.pumpAndSettle();
        await t.tap(button);
        final oldTarget = t.renderObject(button);
        expect(
          t
              .hitTestOnBinding(t.getCenter(button))
              .path
              .any((entry) => entry.target == oldTarget),
          false,
          reason: 'The newly opened modal must shield the old editor launch target.',
        );
        await t.tap(
          button,
          warnIfMissed: false,
        ); // Intentional blocked second click.
        await t.pump();
        final owner = t.state<CommunityProfileDialogState>(
          find.byType(CommunityProfileDialog),
        );
        expect(owner.dialogs, hasLength(1));
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      },
    );
    testWidgets(
      'crop no-pump rapid double apply cannot duplicate native processing $suite',
      (t) async {
        final port = CropPort()..pending = Completer<String>();
        await mount(
          t,
          launch<String>(
            (_) => CommunityLogoCrop(port: port, source: CropPort.source),
            (_) {},
          ),
          suite,
        );
        await action(t, const Key('launch'), 'pointer');
        final f = find.byKey(const Key('community-crop-apply'));
        await t.tap(f);
        await t.tap(f);
        expect(port.calls, hasLength(1));
        port.pending!.complete(FormPort.image);
        await settleCommunityImages(t);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'crop failure retains parameters retry and live reduce $suite',
      (t) async {
        final port = CropPort()..pending = Completer<String>();
        String? result;
        final live = await mount(
          t,
          launch<String>(
            (_) => CommunityLogoCrop(port: port, source: CropPort.source),
            (r) => result = r,
          ),
          suite,
        );
        await action(t, const Key('launch'), 'pointer');
        await slider(t, 'size', 'keyboard');
        final size = value(t, 'size');
        await action(
          t,
          const Key('community-crop-apply'),
          'keyboard',
          settle: false,
        );
        for (final name in ['size', 'horizontal', 'vertical']) {
          expect(
            t.widget<Slider>(find.byKey(ValueKey('crop-$name'))).onChanged,
            isNull,
          );
        }
        live.change(() {
          live.reduce = true;
          live.light = true;
        });
        await t.pump();
        await t.pump();
        port.pending!.completeError(StateError('failed'));
        await settleCommunityImages(t);
        expect(value(t, 'size'), size);
        expect(result, isNull);
        expect(port.calls, hasLength(1));
        port.pending = null;
        await action(t, const Key('community-crop-apply'), 'keyboard');
        expect(result, FormPort.image);
        expect(port.calls, hasLength(2));
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'actual profile crop pending invalidation clears buffer and never uploads $suite',
      (t) async {
        final port = ProfileCropPort();
        port.crop.pending = Completer<String>();
        addTearDown(port.changes.close);
        await mount(
          t,
          CommunityProfileDialog(
            port: port,
            targetRef: 'a' * 32,
            embedded: true,
          ),
          suite,
        );
        await action(t, const Key('profile-pick-logo'), 'keyboard');
        final route =
            ModalRoute.of(t.element(find.byType(CommunityLogoCrop)))!
                as StarBridgeDialogRoute;
        expect(route.instant, true);
        await action(
          t,
          const Key('community-crop-apply'),
          'keyboard',
          settle: false,
        );
        port.changes.add(null);
        await settleCommunityImages(t);
        expect(find.byType(CommunityLogoCrop), findsNothing);
        port.crop.pending!.complete(FormPort.image);
        await settleCommunityImages(t);
        expect(port.saves, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('tag category color painted review $suite', (t) async {
      final capture = GlobalKey();
      await mount(
        t,
        CommunityTagPicker(
          options: options(),
          selected: const ['tag0', 'tag1'],
        ),
        suite,
        capture: capture,
      );
      await settleCommunityImages(t);
      final box =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final rectangles = [
        for (final id in ['tag0', 'tag1'])
          t.getRect(find.byKey(ValueKey('selected-$id'))),
      ];
      await t.runAsync(() async {
        final img = await box.toImage();
        final png = await img.toByteData(format: ImageByteFormat.png);
        final raw = (await img.toByteData(format: ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List();
        for (final rect in rectangles) {
          var text = 0, classification = 0;
          for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
            for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
              final i = (y * img.width + x) * 4;
              if (raw[i] > 180 &&
                  raw[i + 1] > 190 &&
                  raw[i + 2] > 195 &&
                  raw[i + 3] > 240) {
                text++;
              }
              if (raw[i] >= 105 &&
                  raw[i] <= 140 &&
                  raw[i + 1] >= 185 &&
                  raw[i + 1] <= 215 &&
                  raw[i + 2] >= 135 &&
                  raw[i + 2] <= 165 &&
                  raw[i + 3] > 240) {
                classification++;
              }
            }
          }
          expect(
            text,
            greaterThan(5),
            reason: 'Selected caption actually paints.',
          );
          expect(
            classification,
            greaterThan(5),
            reason: 'Original green category edge actually paints.',
          );
        }
        Directory('build/reviews/interaction-batch3ag')
            .createSync(recursive: true);
        File('build/reviews/interaction-batch3ag/${suite.name}-tags.png')
            .writeAsBytesSync(png!.buffer.asUint8List());
        img.dispose();
      });
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
