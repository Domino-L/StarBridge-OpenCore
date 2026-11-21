import 'dart:ui' show ClipOp, Paragraph;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/frame_governor.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_banner.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_controller.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_diagonal.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_hover.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_states.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trend.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_trend_chart.dart';

import '../../support/light_visuals_test_support.dart';
import 'marketplace_test.dart' show FixturePort;

// MaskFilter is stored inside a Picture, rather than an ImageFilterLayer.
// Record the actual painter calls as well as checking the widget layer tree.
class _Paints extends Fake implements Canvas {
  int blurred = 0, sharp = 0;
  void _count(Paint paint) {
    if (paint.maskFilter == null) {
      sharp++;
    } else {
      blurred++;
    }
  }

  @override
  void drawPath(Path path, Paint paint) => _count(paint);
  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => _count(paint);
  @override
  void drawCircle(Offset c, double radius, Paint paint) => _count(paint);
  @override
  void drawRect(Rect rect, Paint paint) => _count(paint);
  @override
  void drawRRect(RRect rrect, Paint paint) => _count(paint);
  @override
  void drawParagraph(Paragraph paragraph, Offset offset) {}
  @override
  void save() {}
  @override
  void restore() {}
  @override
  void clipRect(
    Rect rect, {
    ClipOp clipOp = ClipOp.intersect,
    bool doAntiAlias = true,
  }) {}
  @override
  void clipPath(Path path, {bool doAntiAlias = true}) {}
}

void main() {
  late ValueNotifier<bool> light;
  setUp(() {
    light = ValueNotifier(false);
    debugLightVisualsOverride = light;
  });
  tearDown(() {
    debugLightVisualsOverride = null;
    light.dispose();
  });

  testWidgets('disabled slant action uses paint alpha without a group layer', (
    tester,
  ) async {
    await pumpLightVisuals(
      tester,
      lightVisualsApp(
        const Center(child: MarketSlantButton('disabled', onTap: null)),
      ),
    );
    expect(fractionalOpacityLayers(tester), isNotEmpty);
    final before = tester.getSize(find.byType(MarketSlantButton));
    light.value = true;
    await tester.pump();
    expect(fractionalOpacityLayers(tester), isEmpty);
    expect(tester.getSize(find.byType(MarketSlantButton)), before);
    light.value = false;
    await tester.pump();
    expect(fractionalOpacityLayers(tester), isNotEmpty);
  });

  testWidgets('muted legend uses colour alpha and preserves toggles', (
    tester,
  ) async {
    await pumpLightVisuals(
      tester,
      lightVisualsApp(
        SingleChildScrollView(
          child: MarketplaceTrend([
            for (var i = 1; i <= 3; i++)
              {
                'date': '2026-11-0$i',
                'sellPrice': 1000 + i * 20,
                'buyPrice': 0,
              },
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(fractionalOpacityLayers(tester), isNotEmpty);
    light.value = true;
    await tester.pump();
    expect(fractionalOpacityLayers(tester), isEmpty);
    await tester.tap(
      find.byKey(const ValueKey(('market-trend-legend', 'sell'))),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<MarketTrendChart>(find.byType(MarketTrendChart)).showSell,
      isFalse,
    );
    expect(fractionalOpacityLayers(tester), isEmpty);
  });

  for (final foil in [false, true]) {
    testWidgets('${foil ? 'foil' : 'trend'} omits only its blurred stroke', (
      tester,
    ) async {
      await pumpLightVisuals(
        tester,
        lightVisualsApp(
          Center(
            child: foil
                ? const MarketFoilTag('quality')
                : const SizedBox(
                    width: 500,
                    child: MarketTrendChart(
                      dates: ['one', 'two'],
                      sell: [1000, 1200],
                      buy: [900, 1100],
                      showSell: true,
                      showBuy: true,
                    ),
                  ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paintFinder = foil
          ? find.descendant(
              of: find.byType(MarketFoilTag),
              matching: find.byType(CustomPaint),
            )
          : find.byKey(const Key('market-trend-chart'));
      CustomPainter painter() =>
          tester.widget<CustomPaint>(paintFinder.first).painter!;
      final fullPainter = painter();
      final full = _Paints();
      fullPainter.paint(
        full,
        foil ? const Size(100, 24) : const Size(500, 300),
      );
      expect(full.blurred, 1);
      expect(full.sharp, greaterThan(0));
      // Canvas mask filters do not appear as filter layers even in full mode.
      expect(tester.layers.whereType<ImageFilterLayer>(), isEmpty);
      light.value = true;
      await tester.pump();
      final reduced = _Paints();
      painter().paint(
        reduced,
        foil ? const Size(100, 24) : const Size(500, 300),
      );
      expect(reduced.blurred, 0);
      expect(reduced.sharp, full.sharp);
      expect(painter().shouldRepaint(fullPainter), isTrue);
      expect(tester.layers.whereType<ImageFilterLayer>(), isEmpty);
      light.value = false;
      await tester.pump();
      final restored = _Paints();
      painter().paint(
        restored,
        foil ? const Size(100, 24) : const Size(500, 300),
      );
      expect(restored.blurred, full.blurred);
    });
  }

  testWidgets('drawer entrance ends immediately; its shadow has zero blur', (
    tester,
  ) async {
    const drawerKey = Key('light-drawer');
    await pumpLightVisuals(
      tester,
      lightVisualsApp(
        Center(
          child: MarketHoverCard(
            drawerKey: drawerKey,
            drawer: (_) => const Text('details'),
            child: const SizedBox(width: 200, height: 80, child: Text('card')),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(MarketHoverCard)));
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pump(const Duration(milliseconds: 50));
    expect(fractionalOpacityLayers(tester), isNotEmpty);
    List<BoxShadow> shadows() =>
        (tester
                    .widget<Container>(
                      find
                          .descendant(
                            of: find.byKey(drawerKey),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration)
            .boxShadow!;
    expect(shadows().single.blurRadius, 24);
    light.value = true;
    await tester.pump();
    expect(fractionalOpacityLayers(tester), isEmpty);
    expect(shadows().single.blurRadius, 0);
    // Back to the full look mid-entrance: the drawer stays finished, not
    // half-way, and keeps its content (review CX-C-FULL-073-REVIEW2).
    light.value = false;
    await tester.pump();
    expect(fractionalOpacityLayers(tester), isEmpty);
    expect(find.text('details'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(shadows().single.blurRadius, 24);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'selected hall tab removes its glow immediately on a live mode change',
    (tester) async {
      final c = MarketplaceController(FixturePort());
      addTearDown(c.dispose);
      await pumpLightVisuals(
        tester,
        lightVisualsApp(
          MarketHallHead(c, search: const SizedBox(), onRefresh: null),
        ),
      );
      await tester.pumpAndSettle();
      List<BoxShadow> shadows() => tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .expand((d) => d.boxShadow ?? const <BoxShadow>[])
          .toList();
      expect(shadows().where((s) => s.blurRadius > 0), isNotEmpty);
      light.value = true;
      await tester.pump();
      expect(shadows(), isEmpty);
      expect(tester.layers.whereType<ImageFilterLayer>(), isEmpty);
      light.value = false;
      await tester.pumpAndSettle();
      expect(shadows().where((s) => s.blurRadius == 8), isNotEmpty);
    },
  );
  testWidgets('trend tooltip removes its shadow without moving', (
    tester,
  ) async {
    await pumpLightVisuals(
      tester,
      lightVisualsApp(
        const Center(
          child: SizedBox(
            width: 500,
            child: MarketTrendChart(
              dates: ['one', 'two'],
              sell: [1000, 1200],
              buy: [900, 1100],
              showSell: true,
              showBuy: true,
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const Key('market-trend-chart'))),
    );
    await tester.pump();
    final tip = find.byKey(const Key('market-trend-tip'));
    BoxDecoration decoration() =>
        tester.widget<Container>(tip).decoration! as BoxDecoration;
    final position = tester.getTopLeft(tip);
    expect(decoration().boxShadow!.single.blurRadius, 18);
    light.value = true;
    await tester.pump();
    expect(decoration().boxShadow, isEmpty);
    expect(tester.getTopLeft(tip), position);
    light.value = false;
    await tester.pump();
    expect(decoration().boxShadow!.single.blurRadius, 18);
  });
  testWidgets(
    'refilter preserves full fade timing and snaps only the light transition',
    (tester) async {
      const originalKey = Key('original-opacity');
      Widget surface(bool active) => lightVisualsApp(
        Column(
          children: [
            MarketRefilter(
              active: active,
              onCancel: () {},
              child: const Text('catalog'),
            ),
            AnimatedOpacity(
              key: originalKey,
              opacity: active ? .45 : 1,
              duration: const Duration(milliseconds: 120),
              child: const Text('reference'),
            ),
          ],
        ),
      );
      await pumpLightVisuals(tester, surface(false));
      await pumpLightVisuals(tester, surface(true));
      await tester.pump(const Duration(milliseconds: 40));
      final fadeFinder = find
          .descendant(
            of: find.byType(MarketRefilter),
            matching: find.byType(FadeTransition),
          )
          .first;
      final reference = tester.renderObject<RenderAnimatedOpacity>(
        find.byKey(originalKey),
      );
      final actual = tester.renderObject<RenderAnimatedOpacity>(fadeFinder);
      expect(actual.opacity.value, closeTo(reference.opacity.value, 1e-9));
      light.value = true;
      await tester.pump();
      expect(tester.widget<FadeTransition>(fadeFinder).opacity.value, .45);
      // Persistent .45 remains a single group layer for the arbitrary catalog.
      await pumpLightVisuals(tester, surface(false));
      expect(tester.widget<FadeTransition>(fadeFinder).opacity.value, 1);
      await pumpLightVisuals(tester, const SizedBox());
    },
  );
}
