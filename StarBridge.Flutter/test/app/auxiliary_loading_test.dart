import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/diagnostics/loading_diagnostics.dart';
import 'package:starbridge_flutter/app/diagnostics/loading_tour.dart';
import 'package:starbridge_flutter/app/friends_window/friends_window_app.dart';
import 'package:starbridge_flutter/app/social_windows/social_window_binding.dart';
import 'package:starbridge_flutter/features/notifications/notification_inbox_controller.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

import 'friends_window/friends_window_app_test.dart' as friends;
import 'social_windows/social_window_test.dart' as social;
import '../features/friends/social_layout_test.dart' show loadFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  test('auxiliary traces require local opt-in and have distinct files', () {
    for (final value in [null, '', 'relative.jsonl', r'\\server\trace.jsonl']) {
      final environment = {
        'STARBRIDGE_LOADING_TRACE_PATH': ?value,
        'STARBRIDGE_LOADING_TOUR': 'primary-v1',
      };
      for (final surface in LoadingAuxiliarySurface.values) {
        expect(
          LoadingDiagnostics.auxiliaryTracePath(environment, surface),
          isNull,
        );
      }
    }
    const environment = {'STARBRIDGE_LOADING_TRACE_PATH': r'C:\trace.jsonl'};
    expect(
      LoadingAuxiliarySurface.values
          .map(
            (surface) =>
                LoadingDiagnostics.auxiliaryTracePath(environment, surface),
          )
          .toSet(),
      {
        r'C:\trace.jsonl.friends.jsonl',
        r'C:\trace.jsonl.messages.jsonl',
        r'C:\trace.jsonl.notifications.jsonl',
        r'C:\trace.jsonl.menu.jsonl',
      },
    );
    LoadingDiagnostics.runAuxiliary(
      const {'STARBRIDGE_LOADING_TOUR': 'primary-v1'},
      LoadingAuxiliarySurface.messages,
      () {
        expect(LoadingMetrics.current, isNull);
        expect(
          LoadingDiagnostics.bindTour(
            (_) async => LoadingTourSelection.blocked,
          ),
          isNull,
        );
      },
    );
  });

  testWidgets(
    'primary opening records a numeric generation without snapshot data',
    (tester) async {
      const channel = MethodChannel('starbridge/messages-primary');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final rows = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => 10, write: rows.add);
      var creations = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'show') return false;
        // Native reports window + engine creation once, before revealing.
        if (creations++ == 0) {
          await runZoned(
            () => social.native(channel.name, 'engineCreated', {
              'opening': 1,
              'beginWallUs': 1000,
              'endWallUs': 1400,
            }),
            zoneValues: {loadingMetricsZoneKey: metrics},
          );
        }
        return true;
      });
      final port = social.Port(), inbox = NotificationInboxController(null);
      final binding = SocialWindowBinding(
        kind: 'messages',
        messages: port,
        inbox: inbox,
        navigate: (_) async {},
        channel: channel,
      );
      await runZoned(
        () => binding.open(),
        zoneValues: {loadingMetricsZoneKey: metrics},
      );
      await runZoned(
        () => binding.open(),
        zoneValues: {loadingMetricsZoneKey: metrics},
      );
      expect(rows, [
        {
          'us': 10,
          'kind': 'auxiliaryOpening',
          'surface': 'messages',
          'route': '/messages',
          'phase': 'request',
          'opening': 1,
        },
        {
          'us': 10,
          'kind': 'auxiliaryEngine',
          'surface': 'messages',
          'beginWallUs': 1000,
          'endWallUs': 1400,
        },
        // Only the call that started this opening records when it was shown;
        // a repeated open of a visible window is not a new opening.
        {
          'us': 10,
          'kind': 'auxiliaryOpening',
          'surface': 'messages',
          'route': '/messages',
          'phase': 'shown',
          'opening': 1,
        },
      ]);
      binding.dispose();
      inbox.dispose();
      await port.close();
      messenger.setMockMethodCallHandler(channel, null);
    },
  );

  testWidgets(
    'accepted snapshot paints once per opening and needs actual raster evidence',
    (tester) async {
      const channel = MethodChannel('starbridge/friends-surface');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'ready'
            ? friends.snapshot(name: 'private-display-token')
            : true,
      );
      var time = 10;
      final rows = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
      await runZoned(
        () => tester.pumpWidget(const FriendsWindowApp()),
        zoneValues: {loadingMetricsZoneKey: metrics},
      );
      await runZoned(
        () => tester.pumpAndSettle(),
        zoneValues: {loadingMetricsZoneKey: metrics},
      );
      expect(rows.where((row) => row['kind'] == 'route'), hasLength(1));
      final first = rows.singleWhere((row) => row['kind'] == 'contentPaint');
      expect(first['status'], 'data');
      expect(rows.where((row) => row['kind'] == 'contentRaster'), isEmpty);
      expect(rows.toString(), isNot(contains('private-display-token')));
      expect(rows.toString(), isNot(contains('Pathfinder')));
      // A late previous opening cannot mark a new visit or repaint new content.
      await runZoned(
        () => social.native(
          'starbridge/friends-surface',
          'snapshot',
          friends.snapshot(opening: 0, revision: 9),
        ),
        zoneValues: {loadingMetricsZoneKey: metrics},
      );
      await runZoned(
        () => tester.pumpAndSettle(),
        zoneValues: {loadingMetricsZoneKey: metrics},
      );
      expect(rows.where((row) => row['kind'] == 'route'), hasLength(1));
      time = 20;
      await runZoned(
        () => social.native(
          'starbridge/friends-surface',
          'snapshot',
          friends.snapshot(opening: 2, revision: 1),
        ),
        zoneValues: {loadingMetricsZoneKey: metrics},
      );
      await runZoned(
        () => tester.pumpAndSettle(),
        zoneValues: {loadingMetricsZoneKey: metrics},
      );
      expect(rows.where((row) => row['kind'] == 'route'), hasLength(2));
      expect(rows.where((row) => row['kind'] == 'contentPaint'), hasLength(2));
      time = 100;
      metrics.frame(
        buildUs: 10,
        rasterUs: 10,
        totalUs: 20,
        buildStartUs: 15,
        buildFinishUs: 25,
        rasterFinishUs: 35,
      );
      final raster = rows.singleWhere((row) => row['kind'] == 'contentRaster');
      expect(raster['route'], '/friends');
      expect(raster['visit'], 2);
      expect(raster['us'], 35);
      await tester.pumpWidget(const SizedBox());
      messenger.setMockMethodCallHandler(channel, null);
    },
  );
}
