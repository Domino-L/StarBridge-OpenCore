import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_image_edit.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_workspace.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:flutter/gestures.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts, capture;

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'pure reference keeps image only, hover hint, and stages close pin',
    (tester) async {
      size(tester, const Size(1000, 720));
      late Uint8List png;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 100, 80),
          Paint()..color = Colors.blue,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 80);
        png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List();
        image.dispose();
        picture.dispose();
      });
      final calls = <String>[];
      final tools = MenuLocalToolsController((action, _) async {
        calls.add(action);
        return action == 'imagePinState' ? false : true;
      })..reference = png;
      final workspace = MenuWorkspaceController(
        scope: Object(),
        panels: [
          MenuPanelSpec(
            id: 'image',
            initialBounds: const Rect.fromLTWH(20, 20, 700, 600),
          ),
        ],
      )..open('image');
      tools.referenceView(imageOnly: true);
      await tester.pumpWidget(
        app(
          MenuOverlayWorkspace(
            controller: workspace,
            bridgeStyle: true,
            closeLabel: 'Close',
            moveLabel: 'Move',
            resizeLabel: 'Resize',
            panels: [
              MenuPanelContent(
                id: 'image',
                title: 'Reference',
                icon: StarBridgeIconSemantic.friends,
                chromeHidden: tools.referenceChromeHidden,
                builder: (_, _) =>
                    MenuImageTool(tools: tools, workspace: workspace),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          MemoryImage(png),
          tester.element(find.byType(MenuImageTool)),
        ),
      );
      for (var i = 0; i < 20 && !calls.contains('imagePreparePin'); i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('menu-close-image')).hitTestable(),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('menu-resize-image')).hitTestable(),
        findsNothing,
      );
      expect(find.byType(OutlinedButton).hitTestable(), findsNothing);
      final material = tester.widget<Material>(
        find.byKey(const ValueKey('menu-panel-image')),
      );
      expect(material.type, MaterialType.transparency);
      expect(material.shape, isNull);
      expect(calls, contains('imagePreparePin'));
      expect(calls, isNot(contains('imagePin')));
      expect(tools.pinned, isFalse);
      expect(
        find.byKey(const ValueKey('reference-image-hover-hint')),
        findsNothing,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('reference-image-viewport')),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('reference-image-hover-hint')),
        findsOneWidget,
      );
      await mouse.moveTo(const Offset(900, 680));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('reference-image-hover-hint')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('reference-image-viewport')));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byKey(const ValueKey('reference-image-viewport')));
      await tester.pumpAndSettle();
      expect(tools.referenceImageOnly, isFalse);
      expect(find.byKey(const ValueKey('menu-close-image')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('menu-close-image')));
      await tester.pumpAndSettle();
      expect(calls.last, 'imageCancelPreparedPin');
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
      tools.dispose();
    },
  );
  test('PNG layout metadata is bounded before allocating image views', () {
    final bytes = Uint8List(33);
    bytes.setRange(0, 8, [137, 80, 78, 71, 13, 10, 26, 10]);
    final data = ByteData.sublistView(bytes)
      ..setUint32(8, 13)
      ..setUint32(12, 0x49484452)
      ..setUint32(16, 1920)
      ..setUint32(20, 1080);
    expect(menuPngSize(bytes), const Size(1920, 1080));
    data.setUint32(16, 0);
    expect(menuPngSize(bytes), isNull);
    data.setUint32(16, 20000);
    expect(menuPngSize(bytes), isNull);
    data
      ..setUint32(16, 16000)
      ..setUint32(20, 16000);
    expect(menuPngSize(bytes), isNull);
    expect(menuPngSize(Uint8List(8)), isNull);
  });

  test('pin retains bounds and never acknowledges a newer edit', () async {
    final pending = Completer<Object?>();
    final tools = MenuLocalToolsController((_, _) => pending.future);
    tools.reference = Uint8List.fromList([1]);
    final pin = tools.pin({'x': 10, 'y': 20, 'width': 200, 'height': 100});
    expect(await tools.pin(const {}), isFalse);
    tools.markPinDirty();
    pending.complete(true);
    expect(await pin, isTrue);
    expect(tools.pinned, isTrue);
    expect(tools.pinDirty, isTrue);
    expect(tools.pinnedBounds, const Rect.fromLTWH(10, 20, 200, 100));
    expect(tools.notice, contains('更新固定画面'));
    tools.dispose();
  });
  test(
    'crop composes in rotated original space and rejects invalid selection',
    () {
      const original = MenuImageEdit();
      final first = original.select(const Rect.fromLTRB(.2, .1, .8, .9))!;
      final nested = first.select(const Rect.fromLTRB(.25, .25, .75, .75))!;
      expect(nested.crop.left, closeTo(.35, .00001));
      expect(nested.crop.right, closeTo(.65, .00001));
      final turned = first.rotate();
      expect(turned.turns, 1);
      expect(turned.crop.left, closeTo(.1, .00001));
      expect(turned.crop.top, .2);
      expect(turned.rotate().rotate().rotate().crop.left, closeTo(.2, .00001));
      for (final invalid in [
        Rect.zero,
        const Rect.fromLTRB(-1, 0, 1, 1),
        const Rect.fromLTRB(0, 0, double.nan, 1),
        const Rect.fromLTRB(0, 0, 2, 1),
      ]) {
        expect(original.select(invalid), isNull);
      }
    },
  );

  test(
    'screenshot edits export same recipe, undo without overwriting original',
    () async {
      final original = Uint8List.fromList([1, 2, 3]),
          edited = Uint8List.fromList([4, 5]);
      final calls = <(String, Map<String, Object?>)>[];
      final tools = MenuLocalToolsController((action, args) async {
        calls.add((action, args));
        return switch (action) {
          'capture' => original,
          'screenshotEdit' => edited,
          _ => true,
        };
      });
      await tools.image(capture: true);
      final edit = const MenuImageEdit().select(
        const Rect.fromLTRB(.1, .2, .8, .9),
      )!;
      await tools.editScreenshot(edit);
      expect(identical(tools.screenshot, original), isTrue);
      expect(tools.screenshotPreview, edited);
      expect(calls.map((c) => c.$1), ['capture', 'screenshotEdit']);
      await tools.save(copy: true);
      await tools.save();
      expect(calls[calls.length - 2].$1, 'screenshotCopy');
      expect(calls[calls.length - 2].$2, edit.toMap());
      expect(calls.last.$1, 'save');
      expect(calls.last.$2, {
        ...edit.toMap(),
        'export': {'format': 'png', 'jpegQuality': 90},
      });
      await tools.undoScreenshot();
      expect(tools.screenshotEdit.crop, const Rect.fromLTWH(0, 0, 1, 1));
      expect(tools.canUndo, isFalse);
      await tools.clear(capture: true);
      expect(tools.screenshot, isNull);
      expect(tools.screenshotPreview, isNull);
      tools.dispose();
    },
  );

  test('failed editing preserves preview and undo; cancelled selection preserves pin', () async {
    var failed = false, cancel = false;
    final bytes = Uint8List.fromList([1, 2, 3]);
    final tools = MenuLocalToolsController((action, args) async {
      if (failed) throw StateError('synthetic');
      if (action == 'image' || action == 'capture') {
        return cancel ? null : bytes;
      }
      return true;
    });
    await tools.image();
    await tools.pin(const {});
    expect(tools.pinned, isTrue);
    cancel = true;
    await tools.image();
    expect(tools.reference, bytes);
    expect(tools.pinned, isTrue);
    cancel = false;
    await tools.image(capture: true);
    failed = true;
    await tools.editScreenshot(const MenuImageEdit(turns: 1));
    expect(tools.screenshotPreview, bytes);
    expect(tools.canUndo, isFalse);
    expect(tools.screenshotEdit.turns, 0);
    await tools.clear(unpinOnly: true);
    expect(tools.pinned, isTrue);
    failed = false;
    await tools.clear(unpinOnly: true);
    expect(tools.pinned, isFalse);
    expect(tools.reference, bytes);
    tools.dispose();
  });

  test(
    'pending output cannot duplicate or restore data after disposal',
    () async {
      final pending = Completer<Object?>();
      var count = 0;
      final tools = MenuLocalToolsController((_, _) {
        count++;
        return pending.future;
      });
      tools.screenshot = Uint8List.fromList([1]);
      final one = tools.save(copy: true), two = tools.save();
      expect(count, 1);
      tools.dispose();
      pending.complete(true);
      await one;
      await two;
      expect(tools.screenshot, isNull);
      expect(tools.notice, isEmpty);
    },
  );

  for (final isScreenshot in [false, true]) {
    for (final width in [1000.0, 320.0]) {
      testWidgets('image tool accessible capture=$isScreenshot width=$width', (
        tester,
      ) async {
        size(tester, Size(width, width == 320 ? 240 : 720));
        final calls = <String>[];
        final tools = MenuLocalToolsController((action, _) async {
          calls.add(action);
          return null;
        });
        final key = GlobalKey();
        await tester.pumpWidget(
          app(
            RepaintBoundary(
              key: key,
              child: MediaQuery(
                data: MediaQueryData(
                  textScaler: TextScaler.linear(width == 320 ? 2 : 1),
                ),
                child: MenuImageTool(tools: tools, capture: isScreenshot),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(calls, isEmpty);
        await capture(
          tester,
          key,
          'menu-image-empty-${isScreenshot ? 'capture' : 'reference'}-${width.toInt()}',
        );
        await tester.pumpWidget(const SizedBox());
        tools.dispose();
      });
    }
  }

  testWidgets(
    'loaded image exposes editing and export without automatic writes',
    (tester) async {
      size(tester, const Size(1000, 720));
      late Uint8List png;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 480, 270),
          Paint()..color = const Color(0xff173348),
        );
        canvas.drawRect(
          const Rect.fromLTWH(40, 45, 180, 110),
          Paint()..color = const Color(0xff4cb2f5),
        );
        final picture = recorder.endRecording(),
            image = await picture.toImage(480, 270);
        png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
            .asUint8List();
        image.dispose();
        picture.dispose();
      });
      final calls = <String>[];
      final tools = MenuLocalToolsController((action, _) async {
        calls.add(action);
        return png;
      });
      tools.screenshot = tools.screenshotPreview = png;
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: key,
            child: MenuImageTool(tools: tools, capture: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final imageContext = tester.element(find.byType(MenuImageTool));
      await tester.runAsync(
        () => precacheImage(MemoryImage(png), imageContext),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text('480 × 270'), findsOneWidget);
      await tester.tap(find.text('裁剪'));
      await tester.pumpAndSettle();
      expect(find.text('取消裁剪'), findsOneWidget);
      final area = tester.getRect(
        find
            .byWidgetPredicate(
              (w) => w is GestureDetector && w.onPanStart != null,
            )
            .last,
      );
      await tester.dragFrom(
        area.topLeft + const Offset(30, 30),
        const Offset(140, 80),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '复制截图'))
            .onPressed,
        isNull,
      );
      await capture(tester, key, 'menu-screenshot-crop');
      await tester.tap(find.text('应用裁剪'));
      await tester.pumpAndSettle();
      expect(calls, ['screenshotEdit']);
      expect(tools.screenshotEdit.crop.width, lessThan(1));
      await tester.pumpWidget(const SizedBox());
      tools.reference = png;
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: key,
            child: MenuImageTool(tools: tools),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('旋转'));
      await tester.pumpAndSettle();
      expect(tools.referenceTurns, 1);
      await tester.tap(find.text('放大'));
      await tester.pumpAndSettle();
      expect(tools.referenceTransform.value.getMaxScaleOnAxis(), 1.25);
      tools.referenceChanged(opacity: .5);
      await tester.pumpAndSettle();
      expect(find.text('不透明度 50%'), findsOneWidget);
      expect(calls, ['screenshotEdit']);
      await capture(tester, key, 'menu-reference-editing');
      await tester.pumpWidget(const SizedBox());
      tools.dispose();
    },
  );
}
