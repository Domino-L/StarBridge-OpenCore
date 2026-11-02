import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/diagnostics/loading_tour.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

void main() {
  test('paint without frame evidence times out instead of settling', () async {
    var time = 0;
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
    final tour = LoadingTour(
      metrics,
      wait: (duration) async {
        time += duration.inMicroseconds;
      },
    );
    tour.bind((route) async {
      metrics.route(route);
      metrics.contentPainted(route, LoadingContentStatus.data, items: 1);
      return LoadingTourSelection.workspace;
    });
    await tour.completion;
    final phases = rows.where((r) => r['kind'] == 'tour').toList();
    expect(phases.where((r) => r['phase'] == 'settled'), isEmpty);
    expect(phases.where((r) => r['phase'] == 'timeout'), hasLength(30));
    expect(phases.last['phase'], 'complete');
  });

  test(
    'settles only after real scene evidence and foreground reads finish',
    () async {
      var time = 0;
      final rows = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
      Completer<Object?>? read;
      var readAt = 0;
      void raster(String route, LoadingContentStatus status) {
        final start = time;
        time++;
        metrics.contentPainted(route, status, items: 3);
        time += 2;
        metrics.frame(
          buildUs: 3,
          rasterUs: 1,
          totalUs: 4,
          buildStartUs: start,
          buildFinishUs: time,
          rasterFinishUs: time + 1,
        );
      }

      String? active;
      final tour = LoadingTour(
        metrics,
        wait: (duration) async {
          time += duration.inMicroseconds;
          if (duration == const Duration(milliseconds: 250) && read != null) {
            // Wait more than the settle window; terminal paint alone cannot settle
            // while the request is still pending.
            if (time - readAt >= 4000000) {
              read!.complete(null);
              read = null;
            }
          }
        },
      );
      tour.bind((route) async {
        active = route;
        metrics.route(route);
        read = Completer<Object?>();
        readAt = time;
        metrics.observe('account.getCurrent', read!.future, transport: true);
        raster(route, LoadingContentStatus.partial);
        raster(route, LoadingContentStatus.data);
        return LoadingTourSelection.workspace;
      });
      await tour.completion;
      expect(active, '/');
      final settled = rows.where(
        (r) => r['kind'] == 'tour' && r['phase'] == 'settled',
      );
      expect(settled, hasLength(30));
      expect(
        rows.where((r) => r['kind'] == 'tour' && r['phase'] == 'timeout'),
        isEmpty,
      );
      for (final row in settled) {
        final previous = rows.takeWhile((r) => !identical(row, r));
        final lastRead = previous.lastWhere((r) => r['kind'] == 'transport');
        expect(row['us'] as int, greaterThanOrEqualTo(lastRead['us'] as int));
      }
    },
  );

  test(
    'blocked normal selection stops without accepting or retrying its guard',
    () async {
      var time = 0, selections = 0;
      final rows = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
      final tour = LoadingTour(
        metrics,
        wait: (duration) async {
          time += duration.inMicroseconds;
        },
      );
      tour.bind((_) async {
        selections++;
        return LoadingTourSelection.blocked;
      });
      await tour.completion;
      expect(selections, 1);
      expect(rows.last['phase'], 'blocked');
      expect(rows.where((r) => r['phase'] == 'complete'), isEmpty);
    },
  );

  // Build 12 night sampling (2026-10-21): since DL-131 the shell is built
  // offstage behind the startup screen. The tour started its per-page timer
  // there, so in 17/20 samples /hangar timed out before the shell was shown
  // and never recorded a usable scene.
  test('the tour waits for the visible shell before its first page', () async {
    var time = 0;
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
    final visible = Completer<void>();
    final tour = LoadingTour(
      metrics,
      shellVisible: visible.future,
      wait: (duration) async {
        time += duration.inMicroseconds;
      },
    );
    final routes = <String>[];
    tour.bind((route) async {
      routes.add(route);
      metrics.route(route);
      return LoadingTourSelection.blocked;
    });
    await pumpEventQueue();
    expect(routes, isEmpty);
    expect(rows.where((r) => r['kind'] == 'tour'), isEmpty);
    visible.complete();
    await tour.completion;
    expect(routes, ['/hangar']);
    expect(rows.first['phase'], 'begin');
  });

  // 2026-10-21 user report: the friends, messages and notifications windows
  // stall on open. After the pages, each window opens and hides three times.
  test('after the pages each window opens and hides three times', () async {
    var time = 0;
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
    final tour = LoadingTour(
      metrics,
      wait: (duration) async {
        time += duration.inMicroseconds;
      },
    );
    final calls = <String>[];
    for (final kind in ['friends', 'messages']) {
      tour.registerWindow(
        kind,
        LoadingTourWindow(
          open: () async {
            calls.add('open $kind');
            return kind == 'friends';
          },
          close: () async => calls.add('close $kind'),
        ),
      );
    }
    final unregister = tour.registerWindow(
      'notifications',
      LoadingTourWindow(
        open: () async => fail('an unregistered window is not opened'),
        close: () async {},
      ),
    );
    unregister();
    tour.bind((route) async {
      metrics.route(route);
      metrics.contentPainted(route, LoadingContentStatus.data, items: 1);
      return LoadingTourSelection.workspace;
    });
    await tour.completion;
    expect(calls, [
      for (final kind in ['friends', 'messages'])
        for (var i = 0; i < 3; i++) ...['open $kind', 'close $kind'],
    ]);
    final windows = rows
        .where((r) => r['kind'] == 'tour' && (r['round'] as int) > 2)
        .map((r) => '${r['phase']} ${r['route']} ${r['round']}')
        .toList();
    expect(windows, [
      for (var round = 3; round <= 5; round++) ...[
        'navigate /friends $round',
        'settled /friends $round',
      ],
      for (var round = 3; round <= 5; round++) ...[
        'navigate /messages $round',
        'timeout /messages $round',
      ],
    ]);
    expect(rows.last['phase'], 'complete');
  });

  test('a shell that never reports visible still lets the tour run', () async {
    var time = 0;
    final rows = <Map<String, Object>>[];
    final metrics = LoadingMetrics(nowUs: () => time, write: rows.add);
    final waits = <Duration>[];
    final tour = LoadingTour(
      metrics,
      shellVisible: Completer<void>().future,
      shellVisibleLimit: Duration.zero,
      wait: (duration) async {
        waits.add(duration);
        time += duration.inMicroseconds;
      },
    );
    tour.bind((route) async => LoadingTourSelection.blocked);
    await tour.completion;
    expect(waits.first, const Duration(seconds: 2));
    expect(rows.first['phase'], 'begin');
  });

  test(
    'disposing a bound shell before startup delay prevents navigation',
    () async {
      var selections = 0;
      final delay = Completer<void>();
      final rows = <Map<String, Object>>[];
      final metrics = LoadingMetrics(nowUs: () => 0, write: rows.add);
      final tour = LoadingTour(metrics, wait: (_) => delay.future);
      final unbind = tour.bind((_) async {
        selections++;
        return LoadingTourSelection.workspace;
      });
      unbind();
      delay.complete();
      await tour.completion;
      expect(selections, 0);
      expect(rows, isEmpty);
    },
  );
}
