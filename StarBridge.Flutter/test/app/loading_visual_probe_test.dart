import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_content_probe.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

void main() {
  test('visual bursts cannot evict page evidence or make its waiting content ready', () {
    var time = 10;
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
    metrics.route('/hangar');
    time = 12;
    metrics.contentPainted('/hangar', LoadingContentStatus.waiting, items: 0);
    time = 20;
    for (var i = 0; i < 300; i++) {
      metrics.visualPainted(
        '/hangar',
        LoadingVisualPart.hangarThumbnail,
        LoadingContentStatus.data,
        items: 1,
      );
    }
    time = 100;
    metrics.frame(
      buildUs: 30,
      rasterUs: 10,
      totalUs: 40,
      buildStartUs: 10,
      buildFinishUs: 40,
      rasterFinishUs: 50,
    );
    expect(rows.where((r) => r['kind'] == 'contentRaster'), hasLength(1));
    expect(rows.where((r) => r['kind'] == 'visualRaster'), hasLength(256));
    expect(
      metrics.renderedFor('/hangar', 1)!.status,
      LoadingContentStatus.waiting,
    );
  });

  test('dropped or outgoing image frames cannot report new-page readiness', () {
    var time = 10;
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
    metrics.route('/communities');
    time = 20;
    metrics.visualPainted(
      '/communities',
      LoadingVisualPart.communityImage,
      LoadingContentStatus.data,
      items: 1,
    );
    metrics.frame(buildUs: 1, rasterUs: 1, totalUs: 2);
    expect(rows.where((r) => r['kind'] == 'visualRaster'), isEmpty);
    time = 100;
    metrics.route('/profile');
    metrics.visualPainted(
      '/communities',
      LoadingVisualPart.communityImage,
      LoadingContentStatus.failed,
      items: 0,
    );
    metrics.frame(
      buildUs: 10,
      rasterUs: 10,
      totalUs: 20,
      buildStartUs: 30,
      buildFinishUs: 40,
      rasterFinishUs: 50,
    );
    expect(rows.where((r) => r['kind'] == 'visualPaint'), hasLength(1));
    expect(rows.where((r) => r['kind'] == 'visualRaster'), isEmpty);
    expect(metrics.renderedFor('/profile', 2), isNull);
  });

  testWidgets(
    'visual state requires paint and raster and never serializes image source',
    (tester) async {
      var time = 10;
      final rows = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
      metrics.route('/hangar');
      Future<void> show(double opacity) => runZoned(
        () => tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Opacity(
              opacity: opacity,
              child: LoadingContentProbe(
                route: '/hangar',
                visualPart: LoadingVisualPart.hangarThumbnail,
                status: LoadingContentStatus.data,
                items: 1,
                child: const Text('private-image-source'),
              ),
            ),
          ),
        ),
        zoneValues: {loadingMetricsZoneKey: metrics},
      );
      await show(0);
      expect(rows.where((r) => r['kind'] == 'visualPaint'), isEmpty);
      time = 20;
      await show(1);
      expect(rows.where((r) => r['kind'] == 'visualPaint'), hasLength(1));
      expect(rows.where((r) => r['kind'] == 'visualRaster'), isEmpty);
      time = 100;
      metrics.frame(
        buildUs: 10,
        rasterUs: 10,
        totalUs: 20,
        buildStartUs: 15,
        buildFinishUs: 25,
        rasterFinishUs: 35,
      );
      final row = rows.singleWhere((r) => r['kind'] == 'visualRaster');
      expect(row['part'], 'hangarThumbnail');
      expect(row['us'], 35);
      expect(rows.toString(), isNot(contains('private-image-source')));
      expect(metrics.renderedFor('/hangar', 1), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
