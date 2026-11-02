import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_read_status.dart';

import 'hangar_reader_test.dart' as fixtures;

void main() {
  for (final bookmark in [false, true]) {
    testWidgets(
      'reduced-motion pending hangar status schedules no animation frames, bookmark: $bookmark',
      (tester) async {
        await tester.pumpWidget(
          fixtures.app(
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: LocalHangarReadStatus(
                  snapshot: const LocalHangarSnapshot(revision: 7, ships: []),
                  saved: true,
                  loading: !bookmark,
                  favoriteBusy: bookmark,
                  favoriteFailed: false,
                  failed: false,
                  onRetry: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.binding.hasScheduledFrame, isFalse);
        if (!bookmark) expect(find.text('正在刷新列表…'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
