import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_content_probe.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

void main() {
  testWidgets('only painted, active content can report a render milestone', (
    tester,
  ) async {
    var time = 10;
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
    metrics.route('/hangar');
    Future<void> show(double opacity, LoadingContentStatus status) => runZoned(
      () => tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Opacity(
            opacity: opacity,
            child: LoadingContentProbe(
              route: '/hangar',
              status: status,
              items: 3,
              child: const Text('private-display-name-token'),
            ),
          ),
        ),
      ),
      zoneValues: {loadingMetricsZoneKey: metrics},
    );
    await show(0, LoadingContentStatus.waiting);
    expect(rows.where((r) => r['kind'] == 'contentPaint'), isEmpty);
    time = 20;
    await show(1, LoadingContentStatus.data);
    final mark = rows.singleWhere((r) => r['kind'] == 'contentPaint');
    expect(mark['status'], 'data');
    expect(mark['items'], 3);
    expect(rows.where((r) => r['kind'] == 'contentRaster'), isEmpty);
    expect(rows.toString(), isNot(contains('private')));
    await show(1, LoadingContentStatus.data);
    expect(rows.where((r) => r['kind'] == 'contentPaint'), hasLength(1));
    metrics.route('/profile');
    time = 30;
    await show(1, LoadingContentStatus.partial);
    expect(rows.where((r) => r['kind'] == 'contentPaint'), hasLength(1));
    metrics.route('/hangar');
    time = 40;
    await show(1, LoadingContentStatus.partial);
    expect(rows.where((r) => r['kind'] == 'contentPaint'), hasLength(2));
  });
}
