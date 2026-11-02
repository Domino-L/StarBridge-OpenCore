import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_overview_adapter.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

// Night sampling 2026-10-23: since the fleet page opens on the upper screen,
// no /fleet visit reported usable content (the only probe sat in the members
// list, which paints on the lower screen).
void main() {
  testWidgets('a fleet visit reports content from the upper screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var time = 0;
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => time += 10, write: rows.add);
    await runZoned(() async {
      await tester.pumpWidget(
        StarBridgeApp(
          composition: AppComposition.forTest(
            windowChrome: InMemoryWindowChrome(),
            accountPort: InMemoryAccountAdapter.forReview(
              AccountReviewState.signedIn,
            ),
            officialFleetPort: InMemoryOfficialFleetAdapter.forReview(
              signedIn: true,
            ),
            officialFleetMembersPort:
                InMemoryOfficialFleetMembersAdapter.forReview(),
            officialFleetOverviewPort: UnavailableOfficialFleetOverviewAdapter(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      metrics.route('/fleet');
      await tester.tap(find.byKey(const ValueKey('/fleet')));
      await tester.pumpAndSettle();
    }, zoneValues: {loadingMetricsZoneKey: metrics});
    final paints = rows.where(
      (r) => r['kind'] == 'contentPaint' && r['route'] == '/fleet',
    );
    expect(paints.map((r) => r['status']), contains('data'));
    await tester.pumpWidget(const SizedBox());
  });
}
