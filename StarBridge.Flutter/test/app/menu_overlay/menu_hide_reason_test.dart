import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';
import 'package:starbridge_flutter/shared/diagnostics/menu_open_trace.dart';

void main() {
  test('a hidden menu records only a fixed native reason code', () {
    var time = 1;
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => time++, write: rows.add);
    runZoned(() {
      MenuOpenTrace.windowState(3, 'hidden', 'inputTimeout');
      MenuOpenTrace.windowState(4, 'hidden', 'C:\\private\\path');
      MenuOpenTrace.windowState(5, 'visible', 'inputTimeout');
      MenuOpenTrace.windowState(6, 'hidden');
    }, zoneValues: {loadingMetricsZoneKey: metrics});
    final menu = rows.where((r) => r['kind'] == 'menuOpening').toList();
    expect(menu, hasLength(4));
    expect(menu[0]['phase'], 'hidden');
    expect(menu[0]['reason'], 'inputTimeout');
    expect(menu[1].containsKey('reason'), isFalse, reason: 'unknown dropped');
    expect(menu[2].containsKey('reason'), isFalse, reason: 'hidden only');
    expect(menu[3].containsKey('reason'), isFalse);
    expect(rows.toString(), isNot(contains('private')));
  });
}
