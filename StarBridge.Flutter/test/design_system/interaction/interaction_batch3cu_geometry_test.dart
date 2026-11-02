import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_style.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_recovery_prompt.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show host, detach;
import 'interaction_batch3ct_geometry_test.dart' show pixels;

// Original visible layout only; no copied continuation or storage authority.
class NativeRecoveryOracle extends StatelessWidget {
  const NativeRecoveryOracle({super.key});
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ModalBarrier(dismissible: false, color: BridgeInk.scrim),
      FocusScope(
        autofocus: true,
        child: AlertDialog(
          constraints: const BoxConstraints(maxWidth: 640),
          scrollable: true,
          title: const Text('恢复上次菜单窗口'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text('是否恢复上次打开的窗口？只恢复布局，不恢复聊天草稿、截图或参考图。')],
          ),
          actions: [
            TextButton(onPressed: () {}, child: const Text('恢复窗口')),
            FilledButton(
              autofocus: true,
              onPressed: () {},
              child: const Text('仅打开菜单'),
            ),
          ],
        ),
      ),
    ],
  );
}

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/reviews/interaction-batch3cu');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final width in [320.0, 900.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$suite recovery proportions width=$width text=$scale', (
          t,
        ) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = Size(width, 1000);
          final root = GlobalKey();
          Widget frame(Widget child) => host(
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: root, child: child),
              ),
            ),
            suite,
            reduce: true,
          );
          try {
            List<Rect>? nativeRects;
            List<int>? nativePixels;
            if (suite == InteractionSuite.standard) {
              await t.pumpWidget(frame(const NativeRecoveryOracle()));
              await t.pump();
              await t.pumpAndSettle();
              nativeRects = [
                t.getRect(find.byType(AlertDialog)),
                t.getRect(find.byType(TextButton)),
                t.getRect(find.byType(FilledButton)),
                t.getRect(find.text('恢复上次菜单窗口')),
              ];
              nativePixels = await pixels(t, root);
              await capture(
                t,
                root,
                '${suite.name}-${width.toInt()}-$scale-native-focus',
              );
              await detach(t);
            }
            await t.pumpWidget(frame(MenuRecoveryPrompt(onChoose: (_) {})));
            await t.pump();
            await t.pumpAndSettle();
            final rects = [
              t.getRect(find.byType(AlertDialog)),
              t.getRect(find.byKey(const Key('menu-recovery-restore'))),
              t.getRect(find.byKey(const Key('menu-recovery-start-clean'))),
              t.getRect(find.text('恢复上次菜单窗口')),
            ];
            for (final rect in rects) {
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(width));
              expect(rect.bottom, lessThanOrEqualTo(1000));
            }
            expect(rects[1].overlaps(rects[2]), isFalse);
            if (nativeRects != null) {
              expect(rects, nativeRects);
              final actualPixels = await pixels(t, root);
              final histogram = <int, int>{};
              for (var index = 0; index < actualPixels.length; index++) {
                final delta = (actualPixels[index] - nativePixels![index])
                    .abs();
                if (delta != 0) {
                  histogram.update(
                    delta,
                    (value) => value + 1,
                    ifAbsent: () => 1,
                  );
                }
              }
              debugPrint('RECOVERY_RGBA_DELTAS $width $scale $histogram');
              await capture(
                t,
                root,
                '${suite.name}-${width.toInt()}-$scale-adapter-focus',
              );
              expect(actualPixels, orderedEquals(nativePixels!));
            }
            await capture(
              t,
              root,
              '${suite.name}-${width.toInt()}-$scale-idle',
            );
            await t.tap(find.text('恢复窗口'));
            await t.pump();
            await t.pump(const Duration(milliseconds: 90));
            await capture(
              t,
              root,
              '${suite.name}-${width.toInt()}-$scale-static',
            );
            expect(t.takeException(), isNull);
          } finally {
            await detach(t);
            t.view.reset();
          }
        });
      }
    }
  }
}
