import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_workspace.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_workspace_controller.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';

import '../../features/friends/social_layout_test.dart'
    show app, size, loadFonts;

Rect paintedImage(WidgetTester tester) {
  final box = tester.renderObject<RenderImage>(find.byType(RawImage));
  final image = box.image!;
  final fitted = applyBoxFit(
    BoxFit.contain,
    Size(image.width.toDouble(), image.height.toDouble()),
    box.size,
  );
  final local = Alignment.center.inscribe(
    fitted.destination,
    Offset.zero & box.size,
  );
  return MatrixUtils.transformRect(box.getTransformTo(null), local);
}

void main() {
  setUpAll(loadFonts);
  for (final mode in ['fit', 'actualSize', 'manual']) {
    for (final turns in [0, 1]) {
      testWidgets(
        'pure image preserves screen geometry and window drag: $mode turns=$turns',
        (tester) async {
          size(tester, const Size(1200, 900));
          late Uint8List png;
          await tester.runAsync(() async {
            final recorder = ui.PictureRecorder();
            Canvas(recorder).drawRect(
              const Rect.fromLTWH(0, 0, 100, 80),
              Paint()..color = Colors.blue,
            );
            final picture = recorder.endRecording();
            final image = await picture.toImage(100, 80);
            png = (await image.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List();
            image.dispose();
            picture.dispose();
          });
          final tools = MenuLocalToolsController((_, _) async => false)
            ..reference = png
            ..referenceAutoPinOnClose = false
            ..referenceTurns = turns
            ..referenceScaleMode = mode == 'manual' ? null : mode;
          final workspace = MenuWorkspaceController(
            scope: Object(),
            panels: [
              MenuPanelSpec(
                id: 'image',
                initialBounds: const Rect.fromLTWH(40, 40, 700, 650),
              ),
            ],
          )..open('image');
          var backgroundTaps = 0;
          await tester.pumpWidget(
            app(
              Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => backgroundTaps++,
                  ),
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
          await tester.pumpAndSettle();
          expect(find.text('双击进入纯图片模式'), findsOneWidget);
          if (mode == 'manual') {
            tools.referenceTransform.value = Matrix4.identity()
              ..translateByDouble(-37.0, -29.0, 0, 1)
              ..scaleByDouble(1.7, 1.7, 1.7, 1);
          }
          await tester.pumpAndSettle();
          final transform = tools.referenceTransform.value.clone();
          final before = paintedImage(tester);
          final target = find.byKey(const ValueKey('reference-image-viewport'));
          await tester.tap(target);
          await tester.pump(const Duration(milliseconds: 80));
          await tester.tap(target);
          await tester.pumpAndSettle();
          expect(tools.referenceImageOnly, isTrue);
          expect(paintedImage(tester), before);
          expect(tools.referenceTransform.value, transform);
          expect(
            workspace.paintBoundsFor('image', const Size(1200, 900)),
            tester.getRect(target),
          );
          await tester.tapAt(const Offset(55, 55));
          await tester.pumpAndSettle();
          expect(
            backgroundTaps,
            1,
            reason: 'Hidden chrome must not intercept the window underneath',
          );
          final gesture = await tester.startGesture(tester.getCenter(target));
          await gesture.moveBy(const Offset(30, 20));
          await tester.pump();
          final bounds = workspace.boundsFor('image', const Size(1200, 900));
          final movedFrom = paintedImage(tester);
          await gesture.moveBy(const Offset(40, 30));
          await tester.pump();
          await gesture.up();
          await tester.pumpAndSettle();
          expect(
            workspace.boundsFor('image', const Size(1200, 900)).topLeft,
            bounds.topLeft + const Offset(40, 30),
          );
          expect(paintedImage(tester), movedFrom.shift(const Offset(40, 30)));
          expect(tools.referenceTransform.value, transform);
          final moved = paintedImage(tester);
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(target);
          await tester.pump(const Duration(milliseconds: 80));
          await tester.tap(target);
          await tester.pumpAndSettle();
          expect(tools.referenceImageOnly, isFalse);
          expect(
            workspace.paintBoundsFor('image', const Size(1200, 900)),
            workspace.boundsFor('image', const Size(1200, 900)),
          );
          expect(paintedImage(tester), moved);
          expect(tools.referenceTransform.value, transform);
          await tester.pumpWidget(const SizedBox());
          workspace.dispose();
          tools.dispose();
        },
      );
    }
  }
  test(
    'presentation toggle preserves pin acknowledgement and existing notice',
    () {
      final tools = MenuLocalToolsController((_, _) async => null)
        ..reference = Uint8List.fromList([1])
        ..pinned = true
        ..notice = 'Existing image status';
      final serial = tools.referenceEditSerial;
      tools.referenceView(imageOnly: true);
      expect(tools.pinDirty, isFalse);
      expect(tools.referenceEditSerial, serial);
      expect(tools.notice, 'Existing image status');
      tools.referenceView(imageOnly: false);
      expect(tools.pinDirty, isFalse);
      tools.dispose();
    },
  );
}
