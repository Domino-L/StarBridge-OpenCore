import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_notice_banner.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/design_system/surfaces/starbridge_surface.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/platform/window/menu_notice.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ct_test.dart' show host, closeKey, detach;

const example = MenuNotice(
  '来自舰桥的最新本地通知：验证窄屏标题与按钮对齐',
  '消息仅在当前菜单显示，不改变来源的已读状态，也不打开或关闭任何原生窗口。',
);
const nativeKey = Key('notice-native-oracle-close');

// Original public native layout, no copied timer or notification authority.
class NativeNoticeOracle extends StatelessWidget {
  const NativeNoticeOracle({super.key});
  @override
  Widget build(BuildContext context) => StarBridgeSurface(
    role: SurfaceRole.panel,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                example.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              key: nativeKey,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () {},
              icon: const StandardIcon(StandardIconSemantic.close),
            ),
          ],
        ),
        Text(example.message, maxLines: 4, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}

Future<Uint8List> pixels(WidgetTester t, GlobalKey key) async {
  late Uint8List result;
  await t.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      result = Uint8List.fromList(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
  return result;
}

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('build/reviews/interaction-batch3ct');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png')
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
        testWidgets(
          '$suite notice native geometry and pixels width=$width text=$scale',
          (t) async {
            t.view.devicePixelRatio = 1;
            t.view.physicalSize = Size(width, 1000);
            final root = GlobalKey(), panel = GlobalKey();
            final mouse = await t.createGesture(
              kind: ui.PointerDeviceKind.mouse,
            );
            Widget frame(Widget child) => RepaintBoundary(
              key: root,
              child: host(
                Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: RepaintBoundary(
                      key: panel,
                      child: SizedBox(
                        width: math.min(360, width - 32),
                        child: child,
                      ),
                    ),
                  ),
                ),
                suite,
              ),
            );
            Map<String, Object> geometry(Key button) {
              final box = t.getRect(find.byKey(panel));
              return {
                'size': box.size,
                'button': t.getRect(find.byKey(button)).shift(-box.topLeft),
                'title': t
                    .getRect(find.text(example.title))
                    .shift(-box.topLeft),
                'body': t
                    .getRect(find.text(example.message))
                    .shift(-box.topLeft),
              };
            }

            try {
              await t.pumpWidget(
                frame(const MenuNoticeBanner(notice: example)),
              );
              await t.pumpAndSettle();
              final actual = geometry(closeKey);
              final actualPixels = await pixels(t, panel);
              final name = '${suite.name}-${width.toInt()}-$scale';
              await capture(t, root, '$name-idle');
              await t.pumpWidget(frame(const NativeNoticeOracle()));
              await t.pumpAndSettle();
              expect(actual, geometry(nativeKey));
              final nativePixels = await pixels(t, panel);
              expect(actualPixels.length, nativePixels.length);
              var differences = 0;
              for (var i = 0; i < actualPixels.length; i++) {
                if (actualPixels[i] != nativePixels[i]) differences++;
              }
              expect(
                differences,
                0,
                reason: 'Decoded RGBA, not PNG encoder bytes',
              );
              await t.pumpWidget(
                frame(const MenuNoticeBanner(notice: example)),
              );
              await t.pumpAndSettle();
              await mouse.addPointer(location: Offset.zero);
              await mouse.moveTo(t.getCenter(find.byKey(closeKey)));
              await t.pump();
              await t.pump(const Duration(milliseconds: 800));
              await t.pump(const Duration(milliseconds: 200));
              expect(find.text('关闭'), findsOneWidget);
              await capture(t, root, '$name-hint');
              expect(t.takeException(), isNull);
            } finally {
              await mouse.removePointer();
              await detach(t);
              t.view.reset();
            }
          },
        );
      }
    }
  }
}
