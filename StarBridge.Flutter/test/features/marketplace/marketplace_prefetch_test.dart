import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_prefetch.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_port.dart';

void main() {
  testWidgets(
    'prefetch fills short viewport, serializes requests and stops on failure',
    (tester) async {
      var count = 1, calls = 0, loading = false, failed = false;
      Completer<void>? gate;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MarketPrefetch(
                read: MarketRead({
                  'rows': List.generate(
                    count,
                    (i) => <String, Object?>{'id': i},
                  ),
                  'total': 100,
                }, DateTime.now()),
                loading: loading,
                failed: failed,
                load: () async {
                  calls++;
                  update(() => loading = true);
                  await gate?.future;
                  update(() {
                    count += 20;
                    loading = false;
                  });
                },
                child: ListView.builder(
                  itemExtent: 100,
                  itemCount: count,
                  itemBuilder: (_, i) => Text('$i'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1); // 2100px content exceeds the two-screen buffer.
      gate = Completer<void>();
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(calls, 2);
      gate.complete();
      await tester.pumpAndSettle();
      update(() => failed = true);
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(calls, 2);
    },
  );
  test('empty server page can terminate a stale total', () {
    expect(
      marketHasMore(
        MarketRead({
          'rows': <MarketRow>[],
          'total': 100,
          'pageEnd': true,
        }, DateTime.now()),
      ),
      isFalse,
    );
  });
}
