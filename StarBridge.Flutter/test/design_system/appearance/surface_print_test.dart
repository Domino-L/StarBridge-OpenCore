import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_halloween_theme.dart';
import 'package:starbridge_flutter/design_system/appearance/holiday_theme.dart';
import 'package:starbridge_flutter/design_system/appearance/surface_print.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

void main() {
  test('每种图案都能画出来，不抛异常', () {
    final spec = SurfacePrintSpec(
      tileWidth: 80,
      tileHeight: 80,
      opacity: const {SurfaceRole.ground: .2},
      stamps: [
        for (final motif in PrintMotif.values)
          PrintStamp(
            motif,
            dx: 20,
            dy: 20,
            size: motif == PrintMotif.dot ? 1.5 : 8,
            color: const Color(0xFFFFFFFF),
          ),
      ],
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const SurfacePrintPainter(
      // ignore: avoid_redundant_argument_values
      _Spec.none,
      opacity: .2,
    ).paint(canvas, Size.zero);
    SurfacePrintPainter(spec, opacity: .2).paint(canvas, const Size(300, 200));
    recorder.endRecording().dispose();
  });

  test('圣诞印花：红的旁边没有金，雪银最多', () {
    final stamps = xmasHolidayTheme.printDark.stamps;
    final colors = stamps.map((s) => s.color).toSet();
    expect(colors.length, 4, reason: '雪银、金、红、绿');
    final silver = stamps.where((s) => s.color == stamps.first.color).length;
    expect(silver, greaterThan(stamps.length ~/ 2));
    final red = stamps.firstWhere((s) => s.motif == PrintMotif.bauble);
    final gold = stamps.where((s) => s.motif == PrintMotif.bell).first;
    final distance = Offset(red.dx - gold.dx, red.dy - gold.dy).distance;
    expect(distance, greaterThan(60));
  });

  testWidgets('不在清单里的面不画；在清单里的面有画布', (tester) async {
    final spec = xmasHolidayTheme.printDark;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            SurfacePrint(spec: spec, role: SurfaceRole.navigation),
            SurfacePrint(spec: spec, role: SurfaceRole.panel),
          ],
        ),
      ),
    );
    expect(find.byKey(const Key('surface-print-navigation')), findsOneWidget);
    expect(find.byKey(const Key('surface-print-panel')), findsNothing);
    // 印花不接受任何输入。
    expect(
      find.ancestor(
        of: find.byKey(const Key('surface-print-navigation')),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );
  });

  testWidgets('印花只预先画一次；同样的面共用一张，走了就释放', (tester) async {
    final spec = halloweenHolidayTheme.printDark;
    ui.Image? tile(String role) => (tester
            .widget<CustomPaint>(find.byKey(Key('surface-print-$role')))
            .painter! as SurfacePrintPainter)
        .tile;
    Widget twice() => Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          Expanded(child: SurfacePrint(spec: spec, role: SurfaceRole.ground)),
          Expanded(
            child: SurfacePrint(spec: spec, role: SurfaceRole.navigation),
          ),
        ],
      ),
    );
    await tester.pumpWidget(twice());
    final ground = tile('ground')!;
    final navigation = tile('navigation')!;
    // 浓淡不同，各一张。
    expect(identical(ground, navigation), isFalse);
    await tester.pump();
    await tester.pumpWidget(twice());
    expect(identical(tile('ground'), ground), isTrue, reason: '重建不重画');

    await tester.pumpWidget(const SizedBox());
    expect(ground.debugDisposed, isTrue);
    expect(navigation.debugDisposed, isTrue);
  });

  testWidgets('贴图和直接画的结果一样', (tester) async {
    for (final spec in [
      xmasHolidayTheme.printDark,
      halloweenHolidayTheme.printDark,
    ]) {
      const size = Size(620, 420);
      Future<ui.Image> render(ui.Image? tile) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          Offset.zero & size,
          Paint()..color = const Color(0xFF000000),
        );
        SurfacePrintPainter(spec, opacity: 1, tile: tile).paint(canvas, size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          size.width.toInt(),
          size.height.toInt(),
        );
        picture.dispose();
        return image;
      }

      await tester.runAsync(() async {
        // 用 widget 取到真正的贴图（普通缩放，多画一倍）。
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SurfacePrint(
              spec: SurfacePrintSpec(
                tileWidth: spec.tileWidth,
                tileHeight: spec.tileHeight,
                stamps: spec.stamps,
                opacity: const {SurfaceRole.ground: 1},
              ),
              role: SurfaceRole.ground,
            ),
          ),
        );
        final tile = (tester
                .widget<CustomPaint>(
                  find.byKey(const Key('surface-print-ground')),
                )
                .painter! as SurfacePrintPainter)
            .tile!;
        final vector = await (await render(null)).toByteData();
        final baked = await (await render(tile)).toByteData();
        // 第一块是矢量真值：统计亮度差，允许线条边缘有抗锯齿差异。
        var total = 0, big = 0, lit = 0;
        for (var i = 0; i < vector!.lengthInBytes; i += 4) {
          for (var c = 0; c < 3; c++) {
            final a = vector.getUint8(i + c);
            final b = baked!.getUint8(i + c);
            total += (a - b).abs();
            if ((a - b).abs() > 96) big++;
            if (a > 32) lit++;
          }
        }
        expect(lit, greaterThan(1000), reason: '确实画出了东西');
        // 这是不透明度 1 时的差；实际印花只有 9%～16% 的浓度，差还要小得多。
        expect(total / lit, lessThan(32));
        expect(big / lit, lessThan(.08));
      });
      await tester.pumpWidget(const SizedBox());
    }
  });

  test('四角星路径和品牌标一样是闭合的', () {
    final path = starBridgeStarPath(const Offset(50, 50), 42);
    final bounds = path.getBounds();
    expect(bounds.width, closeTo(80, 1));
    expect(bounds.height, closeTo(84, 1));
  });
}

abstract final class _Spec {
  static const none = SurfacePrintSpec(
    tileWidth: 10,
    tileHeight: 10,
    stamps: [],
    opacity: {},
  );
}
