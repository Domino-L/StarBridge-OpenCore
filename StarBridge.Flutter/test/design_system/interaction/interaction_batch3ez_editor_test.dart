import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_editor.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

Finder key(String value) => find.byKey(Key(value));
Finder save() => key('profile-save');
Finder background() => key('profile-background-picker-open');
Finder field(String name) => key('profile-$name-field');

class EditorProbe {
  EditorProbe(this.suite, this.projection);
  InteractionSuite suite;
  final PersonalProfileProjection projection;
  final editor = GlobalKey<PersonalProfileEditorPanelState>();
  final frame = GlobalKey();
  bool reduce = false, light = false, visible = true;
  bool? requiresReload;
  int cancelled = 0, saved = 0;
  final edits = <PersonalProfileEdit>[];
  final sources = <InteractionSource>[];
  final wallpapers = <(String, InteractionSource)>[];
  Completer<PersonalProfileActionResult> reply = Completer();
  late StateSetter update;
  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return RepaintBoundary(
        key: frame,
        child: scopedApp(
          visible
              ? SingleChildScrollView(
                  child: PersonalProfileEditorPanel(
                    key: editor,
                    projection: projection,
                    moduleLayout: projection.moduleLayout,
                    ownerRequiresReload: requiresReload,
                    onCancel: () => cancelled++,
                    onSaved: () => saved++,
                    onWallpaperChanged: (id) =>
                        wallpapers.add((id, currentStarBridgeActivationSource)),
                    onSave: (value) {
                      edits.add(value);
                      sources.add(currentStarBridgeActivationSource);
                      return reply.future;
                    },
                  ),
                )
              : const Text('away'),
          suite,
          reduce: reduce,
          light: light,
        ),
      );
    },
  );
}

Future<EditorProbe> mountEditor(WidgetTester t, InteractionSuite suite) async {
  size(t, const Size(1100, 1000));
  final source = InMemoryPersonalProfileAdapter.forReview(signedIn: true);
  final projection = PersonalProfileProjection.fromSnapshot(
    await source.read(),
  );
  await source.close();
  final p = EditorProbe(suite, projection);
  await t.pumpWidget(p.app());
  await t.pumpAndSettle();
  return p;
}

FocusNode controlFocus(WidgetTester t, Finder target) {
  final w = t.widget(target);
  if (w is ButtonStyleButton) return w.focusNode!;
  if (w is IconButton) return w.focusNode!;
  return t
      .widget<FocusableActionDetector>(
        find
            .descendant(
              of: target,
              matching: find.byType(FocusableActionDetector),
            )
            .first,
      )
      .focusNode!;
}

Future<void> activateEditor(WidgetTester t, Finder target, String input) async {
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  if (input == 'keyboard') {
    final node = controlFocus(t, target);
    for (var i = 0; !node.hasPrimaryFocus && i < 64; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    expect(node.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else if (input == 'reader') {
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  } else {
    await t.tap(target);
  }
  await t.pump();
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite background preserves native route bounds and touch visibly paints; closing owner retires reverse',
      (t) async {
        final p = await mountEditor(t, suite);
        // Simulate a system-reserved region without changing the real desktop.
        t.view.padding = const FakeViewPadding(top: 90, bottom: 60);
        addTearDown(t.view.resetPadding);
        await activateEditor(t, background(), 'pointer');
        await t.pumpAndSettle();
        final route = ModalRoute.of(
          t.element(key('profile-background-picker-grid')),
        ) as StarBridgeDialogRoute<String>;
        expect(route.traversalEdgeBehavior, TraversalEdgeBehavior.closedLoop);
        final dialog = t.getRect(find.byType(Dialog));
        expect(dialog.top, greaterThanOrEqualTo(90));
        expect(dialog.bottom, lessThanOrEqualTo(940));
        final target = key('profile-wallpaper-target-formation-flight');
        await t.runAsync(
          () => precacheImage(
            const ResizeImage(
              AssetImage('assets/profile-wallpapers/formation-flight.jpg'),
              width: 640,
            ),
            t.element(target),
          ),
        );
        await t.pumpAndSettle();
        final rect = t.getRect(target);
        Future<List<int>> pixels() async => (await t.runAsync(() async {
          final image =
              await (p.frame.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final result = <int>[];
          for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
            for (var x = rect.left.ceil(); x < rect.right.floor(); x++) {
              final at = (y * image.width + x) * 4;
              result.addAll(data!.buffer.asUint8List(at, 4));
            }
          }
          image.dispose();
          return result;
        }))!;
        final before = await pixels();
        await t.pump(const Duration(milliseconds: 150));
        expect(
          await pixels(),
          orderedEquals(before),
          reason: 'Asset decoding is not press feedback',
        );
        final down = await t.startGesture(rect.center);
        await t.pump(const Duration(milliseconds: 150));
        // Material starts its fade on the deadline frame; observe the next
        // rendered frame rather than mistaking its initial zero alpha for rest.
        await t.pump(const Duration(milliseconds: 32));
        final pressed = await pixels();
        expect(
          pressed,
          isNot(orderedEquals(before)),
          reason: 'A running ticker behind opaque fill is not visible feedback',
        );
        await down.cancel();
        await t.pumpAndSettle();
        await activateEditor(
          t,
          key('profile-background-picker-close'),
          'pointer',
        );
        expect(route.animation!.status, AnimationStatus.reverse);
        p.update(() => p.visible = false);
        await t.pump();
        await t.pump();
        await t.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(route.isActive, isFalse);
        expect(p.wallpapers, isEmpty);
        t.view.resetPadding();
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
      skip: const bool.fromEnvironment('STARBRIDGE_PUBLIC_SOURCE'),
    );
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite complete editor $input preserves pending, failure and explicit retry',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final p = await mountEditor(t, suite);
            await t.enterText(field('call-sign'), '  Draft pilot  ');
            await t.enterText(field('about'), 'Private unsaved text');
            expect(
              find.ancestor(
                of: field('call-sign'),
                matching: find.byType(StarBridgeFieldFrame),
              ),
              findsOneWidget,
            );
            expect(
              find.ancestor(
                of: field('about'),
                matching: find.byType(StarBridgeFieldFrame),
              ),
              findsOneWidget,
            );
            final controller = t.widget<TextField>(field('about')).controller;
            await activateEditor(t, save(), input);
            expect(p.edits, hasLength(1));
            expect(p.edits.single.callSign, '  Draft pilot  ');
            expect(p.edits.single.about, 'Private unsaved text');
            expect(p.edits.single.moduleLayout, p.projection.moduleLayout);
            expect(
              p.sources.single,
              input == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(
              p.editor.currentState!.captureDraft().requiresReload,
              isTrue,
            );
            expect(
              t
                  .getSemantics(save())
                  .getSemanticsData()
                  .hasAction(ui.SemanticsAction.tap),
              isFalse,
            );
            expect(
              t
                  .getSemantics(key('profile-edit-cancel'))
                  .getSemanticsData()
                  .hasAction(ui.SemanticsAction.tap),
              isFalse,
            );
            p.update(() {
              p.reduce = true;
              p.light = true;
            });
            await t.pumpAndSettle();
            expect(
              t.widget<TextField>(field('about')).controller,
              same(controller),
            );
            expect(p.edits, hasLength(1));
            p.reply.complete(
              const PersonalProfileActionResult(
                PersonalProfileActionOutcome.failed,
              ),
            );
            await t.pumpAndSettle();
            expect(p.saved, 0);
            expect(
              p.editor.currentState!.captureDraft().edit.about,
              'Private unsaved text',
            );
            p.reply = Completer();
            await activateEditor(t, save(), input);
            expect(p.edits, hasLength(2));
            expect(p.edits.last.about, p.edits.first.about);
            p.reply.complete(
              const PersonalProfileActionResult(
                PersonalProfileActionOutcome.completed,
              ),
            );
            await t.pumpAndSettle();
            expect(p.saved, 1);
            expect(p.cancelled, 0);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite background $input cancels, selects same and changes draft only',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final p = await mountEditor(t, suite);
            await t.enterText(field('about'), 'Keep while choosing');
            await activateEditor(t, background(), input);
            await t.pumpAndSettle();
            expect(
              ModalRoute.of(t.element(key('profile-background-picker-grid'))),
              isA<StarBridgeDialogRoute<String>>(),
            );
            p.update(() {
              p.reduce = true;
              p.light = true;
            });
            await t.pumpAndSettle();
            final ctx = t.element(key('profile-wallpaper-target-none'));
            expect(InteractionScope.of(ctx).reduceMotion, isTrue);
            await activateEditor(
              t,
              key('profile-background-picker-close'),
              input,
            );
            await t.pumpAndSettle();
            expect(find.byType(Dialog), findsNothing);
            expect(p.wallpapers, isEmpty);
            await activateEditor(t, background(), input);
            await t.pumpAndSettle();
            await activateEditor(
              t,
              key('profile-wallpaper-target-none'),
              input,
            );
            await t.pumpAndSettle();
            expect(p.wallpapers, isEmpty);
            await activateEditor(t, background(), input);
            await t.pumpAndSettle();
            // Deliberately finish with a different source: return follows the
            // selection command rather than inheriting the original opener.
            final finalInput = input == 'pointer' ? 'keyboard' : 'pointer';
            await activateEditor(
              t,
              key('profile-wallpaper-target-formation-flight'),
              finalInput,
            );
            await t.pumpAndSettle();
            expect(p.wallpapers, [
              (
                'formation-flight',
                finalInput == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              ),
            ]);
            expect(
              p.editor.currentState!.captureDraft().edit.wallpaperId,
              'formation-flight',
            );
            expect(
              p.editor.currentState!.captureDraft().edit.about,
              'Keep while choosing',
            );
            expect(
              p.edits,
              isEmpty,
              reason: 'Wallpaper selection previews a draft, never saves',
            );
            expect(p.saved, 0);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite empty call sign, conflict and owner reload retain original save gates',
      (t) async {
        final p = await mountEditor(t, suite);
        await t.enterText(field('call-sign'), '   ');
        await t.pumpAndSettle();
        final native = t.widget(save());
        expect(
          native is SuitePressable
              ? native.onActivate
              : (native as ButtonStyleButton).onPressed,
          isNull,
        );
        await t.enterText(field('call-sign'), 'Restore');
        await activateEditor(t, save(), 'pointer');
        p.reply.complete(
          const PersonalProfileActionResult(
            PersonalProfileActionOutcome.rejected,
            requiresReload: true,
          ),
        );
        await t.pumpAndSettle();
        final disabled = t.widget(save());
        expect(
          disabled is SuitePressable
              ? disabled.onActivate
              : (disabled as ButtonStyleButton).onPressed,
          isNull,
        );
        expect(p.saved, 0);
        expect(p.edits, hasLength(1));
        await activateEditor(t, key('profile-edit-cancel'), 'pointer');
        expect(p.cancelled, 1);
        expect(p.editor.currentState!.captureDraft().edit.callSign, 'Restore');
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite background focus hint does not swallow owner Escape; owner disposal closes only own route',
      (t) async {
        final p = await mountEditor(t, suite);
        await activateEditor(t, background(), 'keyboard');
        await t.pumpAndSettle();
        final close = key('profile-background-picker-close');
        final focus = controlFocus(t, close);
        for (var i = 0; !focus.hasPrimaryFocus && i < 64; i++) {
          await t.sendKeyEvent(LogicalKeyboardKey.tab);
          await t.pump();
        }
        expect(focus.hasPrimaryFocus, isTrue);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        await t.pump();
        expect(find.byType(Dialog), findsNothing);
        expect(p.wallpapers, isEmpty);
        await activateEditor(t, background(), 'pointer');
        await t.pumpAndSettle();
        final nav = Navigator.of(
          t.element(key('profile-background-picker-grid')),
        );
        unawaited(
          showStarBridgeDialog<void>(
            nav.context,
            builder: (_) => const AlertDialog(content: Text('Other owner')),
          ),
        );
        await t.pumpAndSettle();
        p.update(() => p.visible = false);
        await t.pump();
        await t.pumpAndSettle();
        expect(key('profile-background-picker-grid'), findsNothing);
        expect(find.text('Other owner'), findsOneWidget);
        nav.pop();
        await t.pumpAndSettle();
        expect(p.edits, isEmpty);
        expect(p.wallpapers, isEmpty);
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite field IME and selection survive live style; pending save after leave cannot call onSaved',
      (t) async {
        final p = await mountEditor(t, suite);
        await t.ensureVisible(field('about'));
        await t.tap(field('about'));
        await t.pump();
        final controller = t.widget<TextField>(field('about')).controller!;
        final focus = t.widget<TextField>(field('about')).focusNode!;
        const value = TextEditingValue(
          text: '输入中draft',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 3),
        );
        controller.value = value;
        p.update(() {
          p.suite = InteractionSuite.glow;
          p.reduce = true;
        });
        await t.pumpAndSettle();
        expect(
          t.widget<TextField>(field('about')).controller,
          same(controller),
        );
        expect(t.widget<TextField>(field('about')).focusNode, same(focus));
        expect(controller.value, value);
        await activateEditor(t, save(), 'keyboard');
        expect(p.edits.single.about, value.text);
        p.update(() => p.visible = false);
        await t.pump();
        p.reply.complete(
          const PersonalProfileActionResult(
            PersonalProfileActionOutcome.completed,
          ),
        );
        await t.pumpAndSettle();
        expect(p.saved, 0);
        expect(find.byType(PersonalProfileEditorPanel), findsNothing);
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
  }
}
