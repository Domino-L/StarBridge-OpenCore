import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_crop_viewport.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_slider.dart';

import '../../app/menu_overlay/menu_reference_crop_test.dart' show pixels;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3cq_support.dart' as image;

Finder opacity() => find.byType(StarBridgeSlider).evaluate().isNotEmpty
    ? find.byType(StarBridgeSlider)
    : find.byType(Slider);

SemanticsNode opacityNode(WidgetTester t) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().flagsCollection.isSlider) nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(t.getSemantics(opacity()));
  expect(nodes, hasLength(1));
  return nodes.single;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite image opacity reader reports and changes real percent locally',
      (t) async {
        final handle = t.ensureSemantics();
        final png = await pixels(t);
        final calls = <String>[];
        final tools = image.owner(png, (action, args) async {
          calls.add(action);
          return null;
        })..referenceOpacity = .6;
        tools.pinned = true;
        await t.pumpWidget(image.ImageHarness(tools, suite));
        await image.cache(t, png);
        await t.ensureVisible(opacity());
        await image.frames(t);
        final node = opacityNode(t);
        expect(node.getSemanticsData().value, '60%');
        final serial = tools.referenceEditSerial;
        t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
          node.id,
          ui.SemanticsAction.increase,
        );
        await image.frames(t);
        expect(tools.referenceOpacity, closeTo(.6425, .000001));
        expect(tools.referenceEditSerial, serial + 1);
        expect(tools.pinDirty, isTrue);
        expect(calls, isEmpty);
        expect(opacityNode(t).getSemanticsData().value, '64%');
        await t.pumpWidget(const SizedBox());
        tools.dispose();
        handle.dispose();
      },
    );
    testWidgets(
      '$suite held image opacity stays direct through reduce then respects busy',
      (t) async {
        final png = await pixels(t);
        final calls = <String>[];
        final tools = image.owner(png, (name, args) async {
          calls.add(name);
          return png;
        })..referenceOpacity = .4;
        final key = GlobalKey<image.ImageHarnessState>();
        await t.pumpWidget(image.ImageHarness(tools, suite, key: key));
        await image.cache(t, png);
        await t.ensureVisible(opacity());
        final rect = t.getRect(opacity());
        final gesture = await t.startGesture(
          Offset(rect.left + rect.width * .4, rect.center.dy),
        );
        await gesture.moveBy(Offset(rect.width * .1, 0));
        await t.pump(const Duration(milliseconds: 120));
        final before = tools.referenceOpacity;
        key.currentState!.change(() => key.currentState!.reduce = true);
        await image.frames(t);
        await gesture.moveBy(Offset(rect.width * .15, 0));
        await t.pump();
        expect(tools.referenceOpacity, greaterThan(before));
        tools.busy = true;
        tools.notifyListeners();
        await image.frames(t);
        final blocked = tools.referenceOpacity;
        await gesture.moveBy(const Offset(25, 0));
        await gesture.up();
        await image.frames(t);
        expect(tools.referenceOpacity, blocked);
        expect(calls, isEmpty);
        tools.busy = false;
        await t.pumpWidget(const SizedBox());
        tools.dispose();
      },
    );
    testWidgets(
      '$suite image owner replacement retires held opacity and cached input',
      (t) async {
        final png = await pixels(t);
        final a = image.owner(png, (_, _) async => null)..referenceOpacity = .4;
        final b = image.owner(png, (_, _) async => null)..referenceOpacity = .8;
        final key = GlobalKey<image.ImageHarnessState>();
        final imageKey = GlobalKey();
        await t.pumpWidget(
          image.ImageHarness(a, suite, key: key, imageKey: imageKey),
        );
        await image.cache(t, png);
        final sameImageElement = imageKey.currentContext;
        await t.ensureVisible(opacity());
        final stale = t.widget<StarBridgeSlider>(opacity()).onChanged!;
        final rect = t.getRect(opacity());
        final gesture = await t.startGesture(rect.center);
        await gesture.moveBy(const Offset(25, 0));
        await t.pump();
        final oldValue = a.referenceOpacity;
        key.currentState!.change(() => key.currentState!.tools = b);
        await image.painted(t);
        expect(imageKey.currentContext, same(sameImageElement));
        stale(.2);
        await gesture.moveBy(const Offset(60, 0));
        await gesture.up();
        await image.frames(t);
        expect(a.referenceOpacity, oldValue);
        expect(b.referenceOpacity, .8);
        expect(b.referenceEditSerial, 0);
        await t.pumpWidget(const SizedBox());
        a.dispose();
        b.dispose();
      },
    );
    for (final screenshot in [false, true]) {
      testWidgets(
        '$suite screenshot=$screenshot native pan follows the same viewport through reduce',
        (t) async {
          final png = await pixels(t);
          final calls = <String>[];
          final tools = image.owner(png, (name, args) async {
            calls.add(name);
            return png;
          }, capture: screenshot);
          final key = GlobalKey<image.ImageHarnessState>();
          await t.pumpWidget(
            image.ImageHarness(tools, suite, key: key, capture: screenshot),
          );
          await image.cache(t, png);
          await image.fire(t, '放大', 'pointer');
          final viewer = find.byType(InteractiveViewer);
          final controller = t
              .widget<InteractiveViewer>(viewer)
              .transformationController!;
          expect(controller.value.getMaxScaleOnAxis(), closeTo(1.25, .00001));
          final first = controller.value.clone();
          final gesture = await t.startGesture(t.getCenter(viewer));
          await gesture.moveBy(const Offset(25, 12));
          await t.pump();
          // Native ScaleGestureRecognizer first accepts at the slop boundary.
          await gesture.moveBy(const Offset(12, 6));
          await t.pump();
          expect(controller.value, isNot(first));
          final before = controller.value.clone();
          key.currentState!.change(() => key.currentState!.reduce = true);
          await image.frames(t);
          expect(
            t.widget<InteractiveViewer>(viewer).transformationController,
            same(controller),
          );
          await gesture.moveBy(const Offset(20, 8));
          await t.pump();
          expect(controller.value, isNot(before));
          await gesture.up();
          await t.pumpAndSettle();
          expect(calls, isEmpty);
          await t.pumpWidget(const SizedBox());
          tools.dispose();
        },
      );
    }
    for (final mode in ['裁剪', '局部放大']) {
      testWidgets(
        '$suite $mode selection and escape do not edit or pin the image',
        (t) async {
          final png = await pixels(t);
          final calls = <String>[];
          final tools = image.owner(png, (name, args) async {
            calls.add(name);
            return png;
          });
          final original = tools.reference;
          await t.pumpWidget(image.ImageHarness(tools, suite));
          await image.cache(t, png);
          await image.fire(t, mode, 'pointer');
          final target = find.byKey(const Key('menu-crop-selection'));
          final rect = t.getRect(target);
          await t.dragFrom(
            rect.topLeft + Offset(rect.width * .2, rect.height * .2),
            Offset(rect.width * .5, rect.height * .5),
          );
          await image.frames(t);
          final selection = t
              .widget<MenuCropViewport>(find.byType(MenuCropViewport))
              .selection;
          expect(selection, isNotNull);
          expect(selection!.width, greaterThan(.2));
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await image.frames(t);
          expect(find.byType(MenuCropViewport), findsNothing);
          expect(tools.reference, same(original));
          expect(tools.referenceEdit.crop, const Rect.fromLTWH(0, 0, 1, 1));
          expect(calls, isEmpty);
          await t.pumpWidget(const SizedBox());
          tools.dispose();
        },
      );
    }
  }
}
