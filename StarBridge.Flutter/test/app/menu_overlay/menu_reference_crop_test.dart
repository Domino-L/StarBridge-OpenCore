import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_image_edit.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;
import 'menu_reference_adjustments_test.dart' show pngHeader, selected;

Future<Uint8List> pixels(
  WidgetTester tester, [
  int width = 240,
  int height = 120,
]) async {
  late Uint8List bytes;
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xff173348),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width / 2, height / 2),
      Paint()..color = const Color(0xff4cb2f5),
    );
    final picture = recorder.endRecording(),
        image = await picture.toImage(width, height);
    bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
    image.dispose();
    picture.dispose();
  });
  return bytes;
}

void main() {
  setUpAll(loadFonts);
  test(
    'region view excludes letterbox and respects rotation and scale limit',
    () {
      const selected = Rect.fromLTWH(0, 0, .5, .5);
      final view = menuImageRegionView(
        const Size(200, 100),
        const Size(400, 400),
        0,
        selected,
        8,
      )!;
      expect(view.scale, 2);
      expect(view.center, const Offset(100, 150));
      final rotated = menuImageRegionView(
        const Size(200, 100),
        const Size(400, 400),
        1,
        selected,
        8,
      )!;
      expect(rotated.center, const Offset(150, 100));
      expect(
        menuImageRegionView(
          const Size(200, 100),
          const Size(400, 400),
          0,
          selected,
          1,
        )!.scale,
        1,
      );
      for (final bad in [
        Rect.zero,
        const Rect.fromLTWH(-.1, 0, .5, .5),
        const Rect.fromLTWH(0, 0, double.nan, .5),
      ]) {
        expect(
          menuImageRegionView(
            const Size(200, 100),
            const Size(400, 400),
            0,
            bad,
            8,
          ),
          isNull,
        );
      }
      expect(
        menuImageRegionView(Size.zero, const Size(400, 400), 0, selected, 8),
        isNull,
      );
      expect(
        menuImageRegionView(const Size(200, 100), Size.zero, 0, selected, 8),
        isNull,
      );
    },
  );
  test('crop, rotate, nested crop, undo and reset use one original and preserve pin', () async {
    final calls = <Map<String, Object?>>[];
    final tools = MenuLocalToolsController((action, args) async {
      if (action == 'image') return selected(1);
      if (action == 'imageEdit') {
        calls.add(args);
        return pngHeader();
      }
      return true;
    });
    addTearDown(tools.dispose);
    await tools.image();
    final original = tools.reference;
    tools.referenceChanged(turns: 1, opacity: .4);
    await tools.pin(const {});
    final edit = tools.referenceEdit.select(
      const Rect.fromLTWH(.25, .2, .5, .6),
    )!;
    await tools.editReference(edit);
    expect(calls.last, edit.toMap());
    expect(identical(original, tools.reference), isTrue);
    expect(tools.pinned, isTrue);
    expect(tools.pinDirty, isTrue);
    expect(tools.referenceOpacity, .4);
    expect(
      tools.referenceDisplayTurns,
      0,
    ); // Native preview already includes rotation.
    tools.referenceChanged(turns: 2);
    expect(tools.referenceDisplayTurns, 1);
    final rotated = edit.rotate(),
        nested = rotated.select(const Rect.fromLTWH(.1, .1, .8, .8))!;
    await tools.editReference(nested);
    expect(calls.last, nested.toMap());
    await tools.undoReference();
    expect(tools.referenceEdit.toMap(), rotated.toMap());
    await tools.editReference(const MenuImageEdit());
    expect(calls.last, const MenuImageEdit().toMap());
    expect(identical(original, tools.reference), isTrue);
    expect(tools.referenceTurns, 0);
    expect(tools.referenceEdit.crop, const Rect.fromLTWH(0, 0, 1, 1));
  });
  test(
    'edit failures and invalid replies preserve preview, undo and transforms',
    () async {
      Object? result = pngHeader();
      final tools = MenuLocalToolsController(
        (action, _) async => action == 'image' ? selected(1) : result,
      );
      addTearDown(tools.dispose);
      await tools.image();
      final edit = const MenuImageEdit().select(
        const Rect.fromLTWH(.1, .1, .8, .8),
      )!;
      await tools.editReference(edit);
      final preview = tools.referencePreview;
      tools.referenceTransform.value = Matrix4.identity()
        ..scaleByDouble(2, 2, 2, 1);
      for (result in <Object?>[
        null,
        false,
        Uint8List(1),
        {'bytes': pngHeader()},
        Uint8List(32 * 1024 * 1024 + 1),
      ]) {
        await tools.editReference(const MenuImageEdit());
        expect(identical(preview, tools.referencePreview), isTrue);
        expect(tools.referenceEdit, edit);
        expect(tools.referenceTransform.value.getMaxScaleOnAxis(), 2);
        expect(tools.canUndoReference, isTrue);
        expect(tools.referenceNoticeKey, 'editFailed');
      }
      result = pngHeader();
      await tools.undoReference();
      expect(tools.canUndoReference, isFalse);
    },
  );
  test('runtime memory regenerates crop from reselected original and restores undo', () async {
    var id = 1, fail = false;
    final tools = MenuLocalToolsController((action, _) async {
      if (action == 'image') return selected(id);
      if (fail) throw StateError('synthetic decoder failure');
      return pngHeader();
    });
    addTearDown(tools.dispose);
    await tools.image();
    final edit = const MenuImageEdit().select(
      const Rect.fromLTWH(.2, .2, .6, .6),
    )!;
    await tools.editReference(edit);
    id = 2;
    await tools.image();
    id = 1;
    await tools.image();
    expect(tools.referenceEdit, edit);
    expect(tools.canUndoReference, isTrue);
    expect(tools.referenceNoticeKey, 'restored');
    await tools.undoReference();
    expect(tools.canUndoReference, isFalse);
    await tools.editReference(edit);
    id = 2;
    await tools.image();
    fail = true;
    id = 1;
    await tools.image();
    expect(tools.referencePreview, isNull);
    expect(tools.referenceEdit.toMap(), const MenuImageEdit().toMap());
    expect(tools.referenceNoticeKey, 'restoreEditFailed');
    expect(tools.referenceAutoPinPending, isFalse);
  });
  test(
    'late edit cannot repopulate closed owner and undo history is bounded',
    () async {
      final pending = Completer<Object?>();
      var delayed = false;
      final tools = MenuLocalToolsController(
        (action, _) async => action == 'image'
            ? selected(1)
            : delayed
            ? pending.future
            : pngHeader(),
      );
      await tools.image();
      for (var n = 0; n < 25; n++) {
        tools.referenceChanged(turns: (tools.referenceTurns + 1) % 4);
      }
      for (var n = 0; n < 20; n++) {
        await tools.undoReference();
      }
      expect(tools.canUndoReference, isFalse);
      delayed = true;
      final edit = tools.editReference(const MenuImageEdit());
      tools.dispose();
      pending.complete(pngHeader());
      await edit;
      expect(tools.referencePreview, isNull);
      expect(tools.reference, isNull);
    },
  );
  for (final locale in AppStrings.supportedLocales) {
    for (final width in [320.0, 1040.0]) {
      for (final mode in ['crop', 'regionZoom']) {
        testWidgets(
          'reference $mode selection and cancellation $locale width=$width',
          (tester) async {
            size(tester, Size(width, width == 320 ? 480 : 900));
            final original = await pixels(tester),
                edited = await pixels(tester, 100, 50);
            final calls = <String>[];
            var dismissed = 0;
            final tools = MenuLocalToolsController((action, _) async {
              calls.add(action);
              return edited;
            });
            tools.reference = original;
            final key = GlobalKey();
            await tester.pumpWidget(
              app(
                Builder(
                  builder: (context) => Localizations.override(
                    context: context,
                    locale: locale,
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(width == 320 ? 1.8 : 1),
                      ),
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(
                            LogicalKeyboardKey.escape,
                          ): () =>
                              dismissed++,
                        },
                        child: RepaintBoundary(
                          key: key,
                          child: MenuImageTool(tools: tools),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.runAsync(
              () => precacheImage(
                MemoryImage(original),
                tester.element(find.byType(MenuImageTool)),
              ),
            );
            await tester.pumpAndSettle();
            final context = tester.element(find.byType(MenuImageTool));
            String text(String n) =>
                AppStrings.of(context).text('menu.image.$n');
            await tester.ensureVisible(find.text(text(mode)));
            await tester.tap(find.text(text(mode)));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, text('actualSize')),
                  )
                  .onPressed,
              isNull,
              reason: 'Selection must not change the underlying view mode',
            );
            tools.referenceAutoPinPending = true;
            tools.settings();
            await tester.pumpAndSettle();
            expect(
              calls,
              isEmpty,
              reason: 'Never auto-pin a selection overlay',
            );
            tools.referenceAutoPinPending = false;
            final area = tester.getRect(
              find.byKey(const Key('menu-crop-selection')),
            );
            await tester.dragFrom(
              area.topLeft + area.size.center(Offset.zero) * .3,
              area.size.center(Offset.zero) * .7,
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await capture(
              tester,
              key,
              'menu-reference-$mode-${locale.toLanguageTag()}-${width.toInt()}',
            );
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(dismissed, 0);
            expect(calls, isEmpty);
            expect(find.byKey(const Key('menu-crop-selection')), findsNothing);
            await tester.ensureVisible(find.text(text(mode)));
            await tester.tap(find.text(text(mode)));
            await tester.pumpAndSettle();
            final again = tester.getRect(
              find.byKey(const Key('menu-crop-selection')),
            );
            await tester.dragFrom(
              again.topLeft + const Offset(15, 15),
              again.size.center(Offset.zero),
            );
            await tester.pumpAndSettle();
            await tester.ensureVisible(
              find.text(text(mode == 'crop' ? 'applyCrop' : 'applyRegion')),
            );
            await tester.tap(
              find.text(text(mode == 'crop' ? 'applyCrop' : 'applyRegion')),
            );
            await tester.pumpAndSettle();
            await tester.runAsync(
              () => precacheImage(
                MemoryImage(edited),
                tester.element(find.byType(MenuImageTool)),
              ),
            );
            await tester.pumpAndSettle();
            expect(calls, mode == 'crop' ? ['imageEdit'] : isEmpty);
            expect(identical(tools.reference, original), isTrue);
            expect(
              tools.referenceEdit.crop.width,
              mode == 'crop' ? lessThan(1) : 1,
            );
            if (mode != 'crop') {
              expect(
                tools.referenceTransform.value.getMaxScaleOnAxis(),
                greaterThan(1),
              );
              expect(tools.referenceScaleMode, isNull);
            }
            expect(tester.takeException(), isNull);
            await capture(
              tester,
              key,
              'menu-reference-$mode-applied-${locale.toLanguageTag()}-${width.toInt()}',
            );
            await tester.pumpWidget(const SizedBox());
            tools.dispose();
          },
        );
      }
    }
  }
}
